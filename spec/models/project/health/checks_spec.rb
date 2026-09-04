# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project::Health::Checks do
  fixtures :all

  describe "GITHUB_REPO_ARCHIVED" do
    let(:check) { described_class::GITHUB_REPO_ARCHIVED }

    it "applies when project has github_repo_archived" do
      project = instance_double Project, github_repo_archived?: true
      expect(check.applies?(project)).to be true
    end

    it "does not apply when project does not have github_repo_archived" do
      project = instance_double Project, github_repo_archived?: false
      expect(check.applies?(project)).to be false
    end
  end

  describe "GITHUB_REPO_GONE" do
    let(:check) { described_class::GITHUB_REPO_GONE }

    it "applies when project has a github_repo_path but no corresponding db record" do
      project = instance_double Project, github_repo_path?: true, github_repo: nil
      expect(check.applies?(project)).to be true
    end

    it "does not apply when project has github_repo" do
      project = instance_double Project, github_repo_path?: true, github_repo: "123"
      expect(check.applies?(project)).to be false
    end

    it "does not apply when project has no github_repo_path" do
      project = instance_double Project, github_repo_path?: false
      expect(check.applies?(project)).to be false
    end
  end

  describe "GITHUB_REPO_NO_COMMIT_ACTIVITY" do
    let(:check) { described_class::GITHUB_REPO_NO_COMMIT_ACTIVITY }

    it "applies when project has a github_repo_repo_pushed_at older than the support window" do
      project = instance_double Project, github_repo_repo_pushed_at: described_class::SUPPORT_WINDOW.ago - 1.minute
      expect(check.applies?(project)).to be true
    end

    it "does not apply when project has no github_repo_repo_pushed_at" do
      project = instance_double Project, github_repo_repo_pushed_at: nil
      expect(check.applies?(project)).to be false
    end

    it "does not apply when project has recent github_repo_repo_pushed_at" do
      project = instance_double Project, github_repo_repo_pushed_at: described_class::SUPPORT_WINDOW.ago + 1.minute
      expect(check.applies?(project)).to be false
    end
  end

  describe "GITHUB_REPO_LOW_COMMIT_ACTIVITY" do
    let(:check) { described_class::GITHUB_REPO_LOW_COMMIT_ACTIVITY }

    it "applies when project has github_repo_average_recent_committed_at older than the bugfix window" do
      allow(described_class::GITHUB_REPO_NO_COMMIT_ACTIVITY).to receive(:applies?)
      project = instance_double Project,
                                github_repo_average_recent_committed_at: described_class::BUGFIX_WINDOW.ago - 1.minute
      expect(check.applies?(project)).to be true
    end

    it "does not apply if no commit activity check applies as well" do
      allow(described_class::GITHUB_REPO_NO_COMMIT_ACTIVITY).to receive(:applies?).and_return(true)
      project = instance_double Project,
                                github_repo_average_recent_committed_at: described_class::BUGFIX_WINDOW.ago - 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when github_repo_average_recent_committed_at is within the bugfix window" do
      allow(described_class::GITHUB_REPO_NO_COMMIT_ACTIVITY).to receive(:applies?)
      project = instance_double Project,
                                github_repo_average_recent_committed_at: described_class::BUGFIX_WINDOW.ago + 1.minute
      expect(check.applies?(project)).to be false
    end
  end

  describe "GITHUB_REPO_OPEN_ISSUES" do
    let(:check) { described_class::GITHUB_REPO_OPEN_ISSUES }

    it "applies when project has more than 5 total issues and closure rate is below 75" do
      project = instance_double Project, github_repo_total_issues_count: 6, github_repo_issue_closure_rate: 74.9
      expect(check.applies?(project)).to be true
    end

    it "does not apply when project does not have more than 5 issues" do
      project = instance_double Project, github_repo_total_issues_count: 5, github_repo_issue_closure_rate: 74.9
      expect(check.applies?(project)).to be false
    end

    it "does not apply when project has high clousre rate" do
      project = instance_double Project, github_repo_total_issues_count: 6, github_repo_issue_closure_rate: 75.1
      expect(check.applies?(project)).to be false
    end

    it "does not apply when project has no issues" do
      project = instance_double Project, github_repo_total_issues_count: nil
      expect(check.applies?(project)).to be false
    end
  end

  describe "PACKAGE_ABANDONED" do
    let(:check) { described_class::PACKAGE_ABANDONED }

    it "applies when package had no release within the support window" do
      project = instance_double Project, package_latest_release_on: described_class::SUPPORT_WINDOW.ago - 1.minute
      expect(check.applies?(project)).to be true
    end

    it "does not apply when package had a release within the support window" do
      project = instance_double Project, package_latest_release_on: described_class::SUPPORT_WINDOW.ago + 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when package had no release" do
      project = instance_double Project, package_latest_release_on: nil
      expect(check.applies?(project)).to be false
    end
  end

  describe "PACKAGE_STALE" do
    let(:check) { described_class::PACKAGE_STALE }

    before do
      allow(described_class::PACKAGE_ABANDONED).to receive(:applies?)
    end

    it "applies when package had no release in more than last year" do
      project = instance_double Project, package_latest_release_on: described_class::RELEASE_CYCLE.ago - 1.minute
      expect(check.applies?(project)).to be true
    end

    it "does not apply when PACKAGE_ABANDONED check applies" do
      allow(described_class::PACKAGE_ABANDONED).to receive(:applies?).and_return(true)
      project = instance_double Project, package_latest_release_on: described_class::RELEASE_CYCLE.ago - 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when package had release within last year" do
      project = instance_double Project, package_latest_release_on: described_class::RELEASE_CYCLE.ago + 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when package had no release" do
      project = instance_double Project, package_latest_release_on: nil
      expect(check.applies?(project)).to be false
    end
  end

  describe "PACKAGE_LONG_RUNNING" do
    let(:check) { described_class::PACKAGE_LONG_RUNNING }

    it "applies when package is older than 5 years and had a release within last year" do
      project = instance_double Project,
                                package_first_release_on:  5.years.ago - 1.minute,
                                package_latest_release_on: described_class::RELEASE_CYCLE.ago + 1.minute
      expect(check.applies?(project)).to be true
    end

    it "does not apply when package is newer than 5 years" do
      project = instance_double Project,
                                package_first_release_on:  5.years.ago + 1.minute,
                                package_latest_release_on: described_class::RELEASE_CYCLE.ago + 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when package has no release within last year" do
      project = instance_double Project,
                                package_first_release_on:  5.years.ago - 1.minute,
                                package_latest_release_on: described_class::RELEASE_CYCLE.ago - 1.minute
      expect(check.applies?(project)).to be false
    end

    it "does not apply when project has no releases" do
      project = instance_double Project,
                                package_first_release_on:  nil,
                                package_latest_release_on: nil
      expect(check.applies?(project)).to be false
    end
  end
end
