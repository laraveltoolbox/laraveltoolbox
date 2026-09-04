# frozen_string_literal: true

require "sidekiq/api"

# Redis handles a few large pushes much better than a flood of small ones
BULK_BATCH_SIZE = 1_000

#
# Everything queued up before a reset refers to packages that are about to be
# discarded, so it is dropped along with them. This also gets redis' memory
# usage back down, which a backlog of several hundred thousand jobs can push
# past what the instance has available.
#
def purge_queues!
  stats = Sidekiq::Stats.new
  puts "Dropping #{stats.enqueued} queued and #{stats.retry_size} retrying jobs..."

  # Sidekiq::Queue.all is a plain array, not an active record relation
  Sidekiq::Queue.all.to_a.each(&:clear)
  Sidekiq::RetrySet.new.clear
  Sidekiq::ScheduledSet.new.clear
rescue RedisClient::Error => e
  # A redis that is down is often exactly why a reset is being run, so it must
  # not stop us from clearing out the database
  warn "Could not reach redis to drop the queues (#{e.class}), continuing anyway"
end

#
# The mirror is rebuilt from scratch, so it goes out via truncation rather than
# record by record: destroying a package cascades into its releases, download
# stats and dependencies one row at a time, which takes hours for a mirror of
# any size.
#
# Categories and category groups survive - the catalog import restores their
# project assignments right afterwards.
#
TRUNCATED_TABLES = %w[
  packages
  package_advisories
  package_code_statistics
  package_dependencies
  package_download_stats
  package_trends
  projects
  categorizations
  github_repos
  github_readmes
].freeze

#
# Without redis the mirror still gets cleared, the rebuild just has to be
# kicked off by hand (or by the hourly cron) once it is back
#
def queue_rebuild!
  CatalogImportJob.perform_async
  PackagesSyncJob.perform_async
rescue RedisClient::Error => e
  warn "Could not reach redis (#{e.class}) - queue CatalogImportJob and PackagesSyncJob once it is back"
end

def discard_mirror!
  connection = ActiveRecord::Base.connection
  tables = TRUNCATED_TABLES.map { connection.quote_table_name(it) }.join(", ")

  connection.execute "TRUNCATE TABLE #{tables} RESTART IDENTITY CASCADE"
end

namespace :packages do
  desc "Discard all mirrored package data and rebuild it from packagist (destructive, requires CONFIRM=yes)"
  task reset: :environment do
    unless ENV["CONFIRM"] == "yes"
      abort "This drops every package, project and their historical data. Re-run with CONFIRM=yes if you mean it."
    end

    puts "Discarding #{Package.count} packages and #{Project.count} projects..."
    purge_queues!
    discard_mirror!

    queue_rebuild!

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
