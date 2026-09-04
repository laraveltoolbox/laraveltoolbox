# frozen_string_literal: true

#
# This class represents historical package download data for a given date and package.
#
# We only store weekly stats, on sundays, to make calculations between timeframes
# more consistent and easy to reason about, as well as saving on database storage
# massively. For the Ruby Toolbox's purposes, weekly stats are just fine(tm).
#
# The weekly persistence of stats happens via the `PackageDownloadsPersistenceJob`,
# which takes a snapshot of whatever current downloads are stored on the `packages`
# table (if package data updating is broken this might be outdated, but again on the
# average week the assumption is that this is good enough for our purposes).
#
# A number of additional stats is calculated using postgres trigger functions, based
# on the presence of previous data:
#
# `absolute_change_(week|month|year)`:
#   The total number of downloads just in that timeframe (if previous record is there)
#
# `relative_change_(week|month|year)`:
#   The percentage of all-time total downloads the timeframe's absolute downloads constitute
#
# `growth_change_(week|month|year)`:
#   The difference between current relative change and the previous one in the timeframe
#
# The trigger functions are not "clever" in triggering related updates if a historical record
# changes (since the assumption is they won't change anyway, it's historical data after all).
# If you change historical numbers, be sure to trigger a re-calculation of all related stats by
# issuing `UPDATE package_download_stats SET id = id (WHERE package_name = 'foo')".
#
class Package::DownloadStat < ApplicationRecord
  belongs_to :package,
             primary_key: :name,
             foreign_key: :package_name,
             inverse_of:  :download_stats

  has_one :project, through: :package

  has_many :trends, class_name:  "Package::Trend",
                    foreign_key: :package_download_stat_id,
                    inverse_of:  :package_download_stat,
                    dependent:   :destroy

  def self.monthly(base_date: Package::DownloadStat.maximum(:date))
    where("(#{table_name}.date <= ?)", base_date)
      .where("(#{table_name}.date - ?) % 28 = 0", base_date)
  end

  def self.with_associations
    includes(:package, :project)
      .joins(:package, :project)
  end
end
