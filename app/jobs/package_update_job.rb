# frozen_string_literal: true

#
# This sidekiq background job takes care of syncing the data
# of one individual composer package from packagist.org to the
# local mirror db
#
# rubocop:disable Metrics/ClassLength -- The remote data mapping is inherently lengthy
class PackageUpdateJob < ApplicationJob
  attr_accessor :name
  private :name=

  def perform(name)
    # This is not nice, but imposed by sidekiq, and we don't want
    # to carry around all that state through all method signatures.
    self.name = name

    if package_data && versions.any?
      changes = perform_updates!

      queue_followups! changes
    else
      Package.where(name:).destroy_all
    end
  end

  private

  def perform_updates!
    Package.transaction do
      changes = update_package_data!
      sync_dependencies!

      changes
    end
  end

  def queue_followups!(changes)
    ProjectUpdateJob.perform_async name
    # Since downloading the package fully is a bit more involved we only want to do
    # it whenever a new version was released
    PackageCodeStatsJob.perform_async name if changes.key?("current_version")
  end

  def update_package_data!
    Package.find_or_initialize_by(name:).tap do |package|
      # Set updated at to ensure we flag what we've pulled
      package.updated_at = package.fetched_at = Time.current.utc
      package.quarterly_release_counts = quarterly_releases
      package.update! mapped_attributes

      return package.previous_changes
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- It's a flat mapping of remote to local attributes
  def mapped_attributes
    {
      authors:                    authors,
      bug_tracker_url:            support["issues"],
      current_version:            current_release.fetch("version"),
      description:                current_release["description"].presence || package_data["description"],
      documentation_url:          support["docs"],
      downloads:                  package_data.dig("downloads", "total").to_i,
      first_release_on:           release_dates.first,
      homepage_url:               current_release["homepage"].presence || package_data["repository"],
      laravel_requirement:        Laravel.requirement_for(runtime_requirements),
      laravel_versions:           Laravel.versions_for(runtime_requirements),
      latest_release_on:          release_dates.last,
      licenses:                   Array(current_release["license"]),
      php_minimum_version:        Composer::Constraint.new(php_requirement).minimum_version,
      php_requirement:            php_requirement,
      releases_count:             versions.count,
      reverse_dependencies_count: package_data["dependents"].to_i,
      source_code_url:            current_release.dig("source", "url").presence || package_data["repository"],
      wiki_url:                   support["wiki"],
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  #
  # The runtime dependencies of the current release. `require-dev` is
  # deliberately excluded - it says nothing about what the package needs to run.
  #
  def runtime_requirements
    @runtime_requirements ||= Hash(current_release["require"])
  end

  def php_requirement
    runtime_requirements["php"]
  end

  def support
    current_release["support"] || {}
  end

  #
  # Composer carries structured author data, we flatten it into the single
  # authors string the schema provides.
  #
  def authors
    Array(current_release["authors"]).filter_map { it["name"].presence }.join(", ").presence
  end

  #
  # The most recent stable release, falling back to the most recent unstable
  # one for packages that never cut a stable release yet.
  #
  def current_release
    @current_release ||= (stable_versions.presence || versions).max_by { comparable_version it }
  end

  def stable_versions
    @stable_versions ||= versions.select { comparable_version(it).release == comparable_version(it) }
  end

  #
  # Composer's normalized versions are dot-separated with an optional stability
  # suffix (`8.3.0.0-beta1`), which `Gem::Version` understands after replacing
  # the separator.
  #
  def comparable_version(version)
    Gem::Version.new version.fetch("version_normalized").sub("-", ".")
  rescue ArgumentError
    Gem::Version.new "0"
  end

  def release_dates
    @release_dates ||= versions.filter_map { Time.zone.parse(it["time"].to_s) }.sort
  end

  def quarterly_releases
    grouped_by_quarter = release_dates.group_by do |released_at|
      "#{released_at.year}-#{(released_at.month / 3.0).ceil}"
    end

    grouped_by_quarter.transform_values(&:count)
  end

  def sync_dependencies!
    known = dependency_requirements.filter_map do |type, dependency_name, requirements|
      next if dependency_name.match? Packagist::PLATFORM_REQUIREMENT

      sync_dependency! dependency_name:, type:, requirements:
    end

    PackageDependency.where(package_name: name).where.not(id: known).delete_all
  end

  def dependency_requirements
    {
      "runtime"     => runtime_requirements,
      "development" => current_release["require-dev"],
    }.flat_map do |type, requirements|
      Hash(requirements).map { |dependency_name, requirement| [type, dependency_name, requirement] }
    end
  end

  def sync_dependency!(dependency_name:, type:, requirements:)
    PackageDependency.find_or_initialize_by(package_name: name, dependency_name:,
                                            type:).tap do |dependency|
      dependency.update!(requirements:)
    end
  end

  def package_data
    return @package_data if defined? @package_data

    @package_data = Packagist.package name
  end

  def versions
    @versions ||= Array(Packagist.versions(name))
  end
end
# rubocop:enable Metrics/ClassLength
