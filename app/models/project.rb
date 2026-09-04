# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength
class Project < ApplicationRecord
  self.primary_key = :permalink

  has_many :categorizations,
           primary_key: :permalink,
           foreign_key: :project_permalink,
           inverse_of:  :project,
           validate:    false,
           dependent:   :destroy

  has_many :categories, through: :categorizations

  belongs_to :package,
             primary_key: :name,
             foreign_key: :package_name,
             optional:    true,
             inverse_of:  :project

  # Projects that are using this project as a dependency on the
  # package definition
  has_many :reverse_dependencies,
           -> { with_score.order(score: :desc) },
           through: :package,
           source:  :reverse_dependency_projects

  has_many :advisories, through: :package

  belongs_to :github_repo,
             primary_key: :path,
             foreign_key: :github_repo_path,
             optional:    true,
             inverse_of:  :projects

  scope :includes_associations, lambda {
    includes(:github_repo, :categories, package: %i[advisories])
      .left_outer_joins(:github_repo, :package, :categories)
  }

  scope :with_score, -> { where.not(score: nil) }

  def self.with_bugfix_forks(include_forks)
    include_forks ? all : where(is_bugfix_fork: false)
  end

  def self.for_display(forks: false)
    includes_associations
      .with_bugfix_forks(forks)
      .with_score
  end

  #
  # Composer package names are prefixed with their vendor, so a plain prefix
  # match would only ever suggest packages when typing the vendor name.
  #
  def self.suggest(name)
    return [] if name.blank?

    Project
      .where("permalink ILIKE ?", "%#{sanitize_sql_like(name)}%")
      .order("score DESC NULLS LAST")
      .limit(25)
      .pluck(:permalink)
  end

  include PgSearch::Model

  pg_search_scope :search_scope,
                  # This is unfortunately not used when using explicit tsvector columns,
                  # see https://github.com/Casecommons/pg_search#using-tsvector-columns
                  against:   { permalink_tsvector: "A", description_tsvector: "C" },
                  using:     {
                    tsearch: {
                      tsvector_column: %w[permalink_tsvector description_tsvector],
                      prefix:          true,
                      dictionary:      "simple",
                    },
                  },
                  ranked_by: ":tsearch * (#{table_name}.score + 1) * (#{table_name}.score + 1)"

  def self.search(query, order: Project::Order.new(directions: Project::Order::SEARCH_DIRECTIONS), show_forks: false)
    with_score
      .with_bugfix_forks(show_forks)
      .search_scope(query)
      .reorder("")
      .includes_associations
      .order(order.sql)
  end

  delegate :current_version,
           :description,
           :documentation_url,
           :downloads,
           :first_release_on,
           :homepage_url,
           :source_code_url,
           :latest_release_on,
           :releases_count,
           :mailing_list_url,
           :changelog_url,
           :wiki_url,
           :bug_tracker_url,
           :licenses,
           :url,
           :reverse_dependencies_count,
           :quarterly_release_counts,
           to:        :package,
           allow_nil: true,
           prefix:    :package

  delegate :stargazers_count,
           :forks_count,
           :homepage_url,
           :watchers_count,
           :description,
           :archived?,
           :repo_pushed_at,
           :wiki_url,
           :issues_url,
           :url,
           :primary_language,
           :has_issues,
           :license,
           :default_branch,
           :is_fork,
           :is_mirror,
           :open_issues_count,
           :closed_issues_count,
           :issue_closure_rate,
           :total_issues_count,
           :open_pull_requests_count,
           :merged_pull_requests_count,
           :closed_pull_requests_count,
           :pull_request_acceptance_rate,
           :average_recent_committed_at,
           :sibling_gem_with_most_downloads,
           :readme,
           to:        :github_repo,
           allow_nil: true,
           prefix:    :github_repo

  def self.find_for_show!(permalink)
    includes_associations
      .includes(github_repo: :readme)
      .find Github.normalize_path(permalink)
  end

  def permalink=(permalink)
    super(Github.normalize_path(permalink))
  end

  # For now we just go with the permalink as the name. In the future
  # this might support canonical human names (i.e. RSpec instead of rspec
  # derived from the package)
  def name
    permalink
  end

  #
  # Projects that are not backed by a packagist package, i.e. those that only
  # exist because the catalog references a github repository directly.
  #
  # Note that composer package names contain a slash just like github repo
  # paths do, so the permalink shape alone cannot tell the two apart.
  #
  def github_only?
    package_name.blank?
  end

  def github_repo_path=(github_repo_path)
    super(Github.normalize_path(github_repo_path))
  end

  alias documentation_url package_documentation_url
  alias changelog_url package_changelog_url
  alias mailing_list_url package_mailing_list_url

  def source_code_url
    package_source_code_url || github_repo_url
  end

  def homepage_url
    package_homepage_url || github_repo_homepage_url
  end

  def wiki_url
    package_wiki_url || github_repo_wiki_url
  end

  def bug_tracker_url
    package_bug_tracker_url || github_repo_issues_url
  end

  def health
    @health ||= Project::Health.new(self)
  end
end
# rubocop:enable Metrics/ClassLength
