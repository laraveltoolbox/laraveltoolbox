# frozen_string_literal: true

#
# Our own historical download stats only start when a package enters the
# mirror, and gaps can appear whenever stats syncing gets stuck.
#
# Packagist exposes per-day download numbers for the whole lifetime of a
# package, which we can walk backwards from the current all-time total to
# reconstruct the weekly totals this app charts.
#
# See also https://packagist.org/apidoc
#
class PackageBackfillStatsJob < ApplicationJob
  # Packagist download statistics don't reach back further than this
  STATS_START_DATE = Date.new 2012, 1, 1

  #
  # Reconstructs weekly (sunday) total download counts for the given package
  # in `date => total_downloads` format, derived from packagist's daily
  # download numbers and the package's current all-time total.
  #
  def self.reconstructed_download_stats(package)
    daily_downloads = Packagist.download_stats package.name, from: STATS_START_DATE
    return {} if daily_downloads.empty?

    running_total = package.downloads
    daily_downloads.keys.sort.reverse.filter_map do |date|
      total_for_date = [running_total, 0].max
      running_total -= daily_downloads.fetch(date, 0)

      [date, total_for_date] if date.sunday?
    end.to_h
  end

  #
  # Figures out the sundays we have no download stats stored for yet
  #
  def self.missing_dates(package, available_dates)
    return [] if available_dates.empty?

    available_dates - package.download_stats.pluck(:date)
  end

  private attr_accessor :package

  def perform(name)
    self.package = Package.find name

    adjusted_count = 0

    missing_dates.each do |date|
      package.download_stats.create! date:, total_downloads: reconstructed_stats.fetch(date)
      adjusted_count += 1
    end

    trigger_the_triggers!

    adjusted_count
  end

  private

  def missing_dates
    @missing_dates ||= self.class.missing_dates package, reconstructed_stats.keys.sort
  end

  def reconstructed_stats
    @reconstructed_stats ||= self.class.reconstructed_download_stats package
  end

  # After filling gaps, we must touch all adjacent records so the derived stats get recalculated
  # Since the stats get calculated with a PG trigger function and we don't have timestamps on this
  # table, we have to force-issue an sql-level update statement for the records (i.e. instead of doing
  # an active record `touch`)
  #
  # rubocop:disable Rails/SkipsModelValidations -- It's fine & intended
  def trigger_the_triggers!
    package.download_stats.where(absolute_change_month: nil).update_all package_name: package.name
  end
  # rubocop:enable Rails/SkipsModelValidations
end
