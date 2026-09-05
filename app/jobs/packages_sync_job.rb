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
# * Everything depending on one of the laravel core packages
# * Everything referenced by the catalog, so curated entries are never dropped
#
class PackagesSyncJob < ApplicationJob
  # The packages virtually every laravel package depends on. Between them their
  # dependents are what makes a composer package a laravel one.
  ROOT_PACKAGES = %w[
    laravel/framework
    illuminate/support
    illuminate/contracts
    illuminate/database
  ].freeze

  #
  # Packagist serves 100 dependents per page and the whole list is walked, so
  # this is a guard against a pagination loop rather than a coverage decision.
  # illuminate/support, by far the widest of the roots, sits at roughly 440
  # pages.
  #
  DEPENDENT_PAGES = 1_000

  LARAVEL_PACKAGE_TYPE = "laravel-package"

  # Redis handles a few large pushes much better than a flood of small ones
  BULK_BATCH_SIZE = 1_000

  # Packages we know nothing about yet get pulled in, packages that vanished
  # upstream get dropped - both is the update job's business.
  #
  # These are pushed in batches: on the initial sync this is tens of thousands
  # of jobs, and pushing them individually overwhelms redis.
  def perform
    PackageUpdateJob.perform_bulk differing_packages.zip, batch_size: BULK_BATCH_SIZE
  end

  def differing_packages
    (remote_packages - local_packages) | (local_packages - remote_packages)
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
