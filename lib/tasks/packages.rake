# frozen_string_literal: true

# Redis handles a few large pushes much better than a flood of small ones
BULK_BATCH_SIZE = 1_000

namespace :packages do
  desc "Discard all mirrored package data and rebuild it from packagist (destructive, requires CONFIRM=yes)"
  task reset: :environment do
    unless ENV["CONFIRM"] == "yes"
      abort "This drops every package, project and their historical data. Re-run with CONFIRM=yes if you mean it."
    end

    puts "Discarding #{Package.count} packages and #{Project.count} projects..."

    # Packages cascade into their projects, dependencies, download stats,
    # trends, advisories and code statistics
    Package.in_batches(&:destroy_all)
    # Github-only projects have no package to cascade from
    Project.in_batches(&:destroy_all)
    GithubRepo.without_projects.destroy_all

    CatalogImportJob.perform_async
    PackagesSyncJob.perform_async

    puts "Queued the catalog import and a full packagist sync."
    puts "The sync enqueues one update job per package, so expect the mirror to fill up over the next hours."
  end

  desc "Queue historical download stats backfill for all mirrored packages"
  task backfill_stats: :environment do
    names = Package.pluck(:name)
    # Pushing tens of thousands of jobs one by one exhausts redis' patience,
    # so they go over in batches
    PackageBackfillStatsJob.perform_bulk names.zip, batch_size: BULK_BATCH_SIZE

    puts "Queued download stats backfill for #{names.count} packages."
  end
end
