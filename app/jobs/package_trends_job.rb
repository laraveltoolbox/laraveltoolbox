# frozen_string_literal: true

#
# This job detects trending projects for a given date
# based on Package::DownloadStats and persists them in the Package::Trend
# model for easier querying and stable results over time (if the
# calculation changes down the road)
#
class PackageTrendsJob < ApplicationJob
  sidekiq_options queue: :priority

  def perform(date)
    date = Date.parse date

    Package::Trend.transaction do
      Package::Trend.where(date:).destroy_all
      trending_stats_for(date).each.with_index do |stat, i|
        Package::Trend.create! package:               stat.package,
                               date:,
                               position:              i + 1,
                               package_download_stat: stat
      end
    end
  end

  private

  def trending_stats_for(date)
    Package::DownloadStat
      .merge(trending_scope)
      .where(date:)
      .with_associations
      .limit(48)
  end

  def trending_scope
    Package::DownloadStat
      .where.not(relative_change_month: nil) # Stats need to be present xD
      .where.not(growth_change_month: nil)
      .where("absolute_change_month > ?", 10_000) # Baseline minimum downloads to be considered "trending"
      .where("growth_change_month > ?", 0) # Month-over-month growth must be positive to be trending
      .where("packages.latest_release_on > ?", 6.months.ago) # Must have had a recent release
      .merge(Project.with_bugfix_forks(false))
      .order(relative_change_month: :desc)
  end
end
