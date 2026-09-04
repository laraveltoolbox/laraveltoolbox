# frozen_string_literal: true

class ProjectScoreJob < ApplicationJob
  attr_accessor :project
  private :project=

  def perform(permalink)
    self.project = Project.includes_associations.find permalink

    project.update! score:                calculated_score,
                    is_bugfix_fork:       bugfix_fork?,
                    bugfix_fork_of:,
                    bugfix_fork_criteria:
  end

  private

  def calculated_score
    scores = [package_score, github_repo_score].compact
    return if scores.empty?

    scores.sum / scores.count
  end

  delegate :package, :github_repo, to: :project

  def package_score
    return unless package

    package.downloads * 100.0 / package.class.maximum(:downloads)
  end

  def github_repo_score
    return unless github_repo

    (github_repo.stargazers_count + (github_repo.forks_count * 5)) * 100.0 / github_ceiling
  end

  def github_ceiling
    github_repo.class.maximum(:stargazers_count) + (github_repo.class.maximum(:forks_count) * 5)
  end

  def fork_detector
    @fork_detector ||= Project::ForkDetector.new(project)
  end

  def bugfix_fork?
    bugfix_fork_of.present?
  end

  def bugfix_fork_of
    fork_detector.forked_from
  end

  def bugfix_fork_criteria
    fork_detector.fork_criteria
  end
end
