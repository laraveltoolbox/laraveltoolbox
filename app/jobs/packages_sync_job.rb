# frozen_string_literal: true

#
# This sidekiq background job compares the set of laravel-related
# packages published on packagist.org against the packages present
# in the local mirror and queues updates on differing packages.
#
# Packagist hosts every composer package there is, the vast majority of
# which has nothing to do with laravel. We therefore mirror a focused
# subset:
#
# * Everything published with the `laravel-package` composer type
# * The most-downloaded dependents of the laravel core packages
# * Everything referenced by the catalog, so curated entries are never dropped
#
class PackagesSyncJob < ApplicationJob
  # The packages virtually every laravel package depends on. Their dependents
  # are ordered by downloads, so the truncation below keeps the relevant ones.
  ROOT_PACKAGES = %w[
    laravel/framework
    illuminate/support
    illuminate/contracts
    illuminate/database
  ].freeze

  # 100 dependents are returned per page, so this caps the mirror at roughly
  # 2000 dependents per root package (minus the sizable overlap between them)
  DEPENDENT_PAGES = 20

  LARAVEL_PACKAGE_TYPE = "laravel-package"

  def perform
    (remote_packages - local_packages).each do |locally_missing_package|
      PackageUpdateJob.perform_async locally_missing_package
    end

    (local_packages - remote_packages).each do |remotely_missing_package|
      PackageUpdateJob.perform_async remotely_missing_package
    end
  end

  def local_packages
    @local_packages ||= Package.pluck(:name)
  end

  def remote_packages
    @remote_packages ||= (typed_packages | dependent_packages | catalog_packages).uniq
  end

  private

  def typed_packages
    Packagist.package_names type: LARAVEL_PACKAGE_TYPE
  end

  def dependent_packages
    ROOT_PACKAGES.flat_map do |root_package|
      Packagist.dependents root_package, max_pages: DEPENDENT_PAGES
    end
  end

  #
  # Curated packages must never be dropped from the mirror just because they
  # happen to sit outside of the download-ranked subset above
  #
  def catalog_packages
    Categorization.distinct.pluck(:project_permalink)
  end
end
