# frozen_string_literal: true

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
    names.each { PackageBackfillStatsJob.perform_async it }

    puts "Queued download stats backfill for #{names.count} packages."
  end
end
