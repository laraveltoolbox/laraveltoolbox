# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Full Project Sync", :clean_database, :real_http, :sidekiq_inline do
  fixtures :all

  describe "for packagist-based projects", vcr: { cassette_name: "full-project-sync-from-packagist" } do
    let(:package_name) { "spatie/laravel-permission" }
    let(:do_perform) { PackageUpdateJob.perform_async package_name }

    before do
      # Syncing the github repo requires API credentials, it is covered by the
      # github-based project sync below
      allow(GithubRepoUpdateJob).to receive(:perform_async)
      # Code statistics download the full package source, they have their own spec
      allow(PackageCodeStatsJob).to receive(:perform_async)
    end

    it "creates the project" do
      expect { do_perform }.to change { Project.where(permalink: package_name).count }.from(0).to(1)
    end

    it "assigns the expected attributes to the resulting project" do
      do_perform
      expect(Project.find(package_name)).to have_attributes(
        package_name:,
        github_repo_path:  "spatie/laravel-permission",
        package_downloads: (a_value > 10_000_000),
        score:             (a_value > 0)
      )
    end
  end

  describe "for github-based projects", vcr: { cassette_name: "full-project-sync-from-github" } do
    let(:do_perform) { ProjectUpdateJob.perform_async "postmodern/chruby" }

    it "creates the project" do
      expect { do_perform }.to change { Project.where(permalink: "postmodern/chruby").count }.from(0).to(1)
    end

    it "assigns the expected attributes to the resulting project" do
      do_perform
      expect(Project.find("postmodern/chruby")).to have_attributes(
        package_name:                 nil,
        github_repo_path:             "postmodern/chruby",
        github_repo_stargazers_count: (a_value > 1500),
        github_repo_forks_count:      (a_value > 100),
        score:                        100.0
      )
    end
  end
end
