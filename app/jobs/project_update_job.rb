# frozen_string_literal: true

class ProjectUpdateJob < ApplicationJob
  # Some packages reference a github repo they have no affiliation with,
  # for example a javascript library they merely wrap. Since the referenced
  # repo's popularity metrics (stars, forks) feed into the overall popularity
  # score, this skews the scoring - so those packages are prevented from
  # linking against their referenced github repo.
  REPO_LINK_BLACKLIST = [].freeze

  #
  # Some packages reference an upstream code generator or similar tool
  # that are technically unrelated but have a lot of github stars etc,
  # leading to inflated popularity scores.
  #
  # This blacklist prevents references to those github repos.
  #
  TEMPLATE_REPO_BLACKLIST = %w[
    swagger-api/swagger-codegen
  ].freeze

  def perform(permalink)
    Project.find_or_initialize_by(permalink:).tap do |project|
      project.package = Package.find_by(name: permalink)
      project.github_repo_path = detect_repo_path(project)
      project.description = project.package_description || project.github_repo_description
      project.save!
      ProjectScoreJob.perform_async permalink
      ProjectSearchIndexJob.perform_async permalink
      enqueue_github_repo_sync project.github_repo_path
    end
  end

  private

  def detect_repo_path(project)
    if project.github_only?
      project.permalink
    else
      return unless project.package
      return if REPO_LINK_BLACKLIST.include? project.package_name

      name = Github.detect_repo_name project.package.homepage_url,
                                     project.package.source_code_url,
                                     project.package.bug_tracker_url
      name unless TEMPLATE_REPO_BLACKLIST.include? name
    end
  end

  def enqueue_github_repo_sync(path)
    return if path.nil? || GithubRepo.find_by(path:)

    GithubRepoUpdateJob.perform_async path
  end
end
