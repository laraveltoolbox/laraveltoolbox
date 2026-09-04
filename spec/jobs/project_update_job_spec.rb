# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectUpdateJob do
  fixtures :all

  let(:job) { described_class.new }
  let(:do_perform) { job.perform permalink }
  let(:permalink) { "spatie/laravel-permission" }

  describe "#perform" do
    it "creates the project if not existent yet" do
      expect { do_perform }.to change { Project.find_by(permalink:) }
        .from(nil).to(kind_of(Project))
    end

    it "does not create another project if present" do
      Project.create!(permalink:)
      expect { do_perform }.not_to(change(Project, :count))
    end

    it "assigns an existing package if matching" do
      project = Project.create!(permalink:)
      PackageUpdateJob.new.perform(permalink)
      package = Package.find(permalink)
      expect { do_perform }.to change { project.reload.package }.from(nil).to(package)
    end

    [ProjectScoreJob, ProjectSearchIndexJob].each do |job_type|
      it "enqueues a #{job_type}" do
        expect(job_type).to receive(:perform_async).with(permalink)
        do_perform
      end
    end

    describe "github repo detection" do
      let(:project) { Project.create! permalink: }

      before do
        PackageUpdateJob.new.perform(permalink)
      end

      it "assigns a github_repo_path if detected in package urls" do
        expect { do_perform }.to change { project.reload.github_repo_path }.from(nil).to("spatie/laravel-permission")
      end

      it "assigns nil github_repo_path when package name is blacklisted" do
        project.update! github_repo_path: "foo/bar"
        stub_const "#{described_class}::REPO_LINK_BLACKLIST", [project.permalink]
        expect { do_perform }.to change { project.reload.github_repo_path }.to(nil)
      end

      it "assigns nil github_repo_path when found github repo path is blacklisted" do
        project.update! github_repo_path: "foo/bar"
        allow(Github).to receive(:detect_repo_name).and_return("foo/bar")
        stub_const "#{described_class}::TEMPLATE_REPO_BLACKLIST", %w[foo/bar]
        expect { do_perform }.to change { project.reload.github_repo_path }.to(nil)
      end

      it "enqueues a GithubRepoUpdateJob if the github repo is missing" do
        expect(GithubRepoUpdateJob).to receive(:perform_async).with("spatie/laravel-permission")
        do_perform
      end

      it "does not enqueue a GithubRepoUpdateJob if the github repo exists" do
        GithubRepo.create! path: "spatie/laravel-permission", stargazers_count: 0, watchers_count: 0, forks_count: 0
        expect(GithubRepoUpdateJob).not_to receive(:perform_async)
        do_perform
      end

      it "does not enqueue a GithubRepoUpdateJob if no repo is referenced" do
        Package.find(permalink).update! homepage_url: nil, source_code_url: nil, bug_tracker_url: nil
        expect(GithubRepoUpdateJob).not_to receive(:perform_async)
        do_perform
      end
    end

    describe "for github-only project" do
      let(:permalink) { "laravel/laravel" }

      it "assigns permalink as the github_repo_path for github-only projects" do
        project = Project.create!(permalink:)
        expect { do_perform }.to change { project.reload.github_repo_path }.from(nil).to(permalink)
      end
    end
  end
end
