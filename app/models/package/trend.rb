# frozen_string_literal: true

class Package::Trend < ApplicationRecord
  belongs_to :package,
             primary_key: :name,
             foreign_key: :package_name,
             inverse_of:  :trends

  belongs_to :package_download_stat,
             class_name: "Package::DownloadStat",
             inverse_of: :trends

  has_one :project, through: :package
  has_one :github_repo, through: :project

  delegate :absolute_change_month,
           :relative_change_month,
           :growth_change_month,
           to: :package_download_stat

  def self.with_associations
    includes(:package_download_stat, project: %i[package github_repo])
      .joins(:package_download_stat, project: %i[package github_repo])
  end

  def self.latest
    for_date maximum(:date)
  end

  def self.for_date(date)
    where(date:)
      .with_associations
      .order(position: :asc)
  end
end
