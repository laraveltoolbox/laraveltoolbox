# frozen_string_literal: true

module Project::Health::Checks
  #
  # Laravel ships a new major version roughly every year and supports each one
  # with bug fixes for 18 months and security fixes for 2 years. Maintenance
  # gaps are therefore judged against that cadence rather than against the
  # much slower one these checks were originally written for.
  #
  # See https://laravel.com/docs/releases#support-policy
  #
  RELEASE_CYCLE = 1.year
  BUGFIX_WINDOW = 18.months
  SUPPORT_WINDOW = 2.years

  GITHUB_REPO_ARCHIVED = Project::Health::Status.new(:github_repo_archived, :red, :github, &:github_repo_archived?)

  GITHUB_REPO_GONE = Project::Health::Status.new(:github_repo_gone, :red, :github) do |project|
    project.github_repo_path? &&
      project.github_repo.nil?
  end

  GITHUB_REPO_NO_COMMIT_ACTIVITY = Project::Health::Status.new(:no_commit_activity, :red, :github) do |project|
    project.github_repo_repo_pushed_at &&
      project.github_repo_repo_pushed_at < SUPPORT_WINDOW.ago
  end

  GITHUB_REPO_LOW_COMMIT_ACTIVITY = Project::Health::Status.new(:low_commit_activity, :yellow, :github) do |project|
    !GITHUB_REPO_NO_COMMIT_ACTIVITY.applies?(project) &&
      project.github_repo_average_recent_committed_at &&
      project.github_repo_average_recent_committed_at < BUGFIX_WINDOW.ago
  end

  GITHUB_REPO_OPEN_ISSUES = Project::Health::Status.new(:github_repo_open_issues, :yellow, :github) do |project|
    project.github_repo_total_issues_count &&
      project.github_repo_total_issues_count > 5 &&
      project.github_repo_issue_closure_rate < 75
  end

  PACKAGE_ABANDONED = Project::Health::Status.new(:package_abandoned, :red, :diamond) do |project|
    project.package_latest_release_on &&
      project.package_latest_release_on < SUPPORT_WINDOW.ago
  end

  PACKAGE_STALE = Project::Health::Status.new(:package_stale, :yellow, :diamond) do |project|
    !PACKAGE_ABANDONED.applies?(project) &&
      project.package_latest_release_on &&
      project.package_latest_release_on < RELEASE_CYCLE.ago
  end

  PACKAGE_LONG_RUNNING = Project::Health::Status.new(:package_long_running, :green, :diamond) do |project|
    project.package_latest_release_on &&
      project.package_first_release_on &&
      project.package_first_release_on < 5.years.ago &&
      project.package_latest_release_on > RELEASE_CYCLE.ago
  end

  ALL = [
    GITHUB_REPO_ARCHIVED,
    GITHUB_REPO_GONE,
    GITHUB_REPO_NO_COMMIT_ACTIVITY,
    PACKAGE_ABANDONED,
    GITHUB_REPO_LOW_COMMIT_ACTIVITY,
    GITHUB_REPO_OPEN_ISSUES,
    PACKAGE_STALE,
    PACKAGE_LONG_RUNNING,
  ].freeze
end
