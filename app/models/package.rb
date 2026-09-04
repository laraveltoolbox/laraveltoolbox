# frozen_string_literal: true

class Package < ApplicationRecord
  self.primary_key = :name

  has_one :project,
          primary_key: :name,
          foreign_key: :package_name,
          inverse_of:  :package,
          dependent:   :destroy

  has_many :advisories, -> { order(date: :desc) },
           class_name:  "Package::Advisory",
           primary_key: :name,
           foreign_key: :package_name,
           inverse_of:  :package,
           dependent:   :destroy

  has_many :download_stats, -> { order(date: :asc) },
           class_name:  "Package::DownloadStat",
           primary_key: :name,
           foreign_key: :package_name,
           inverse_of:  :package,
           dependent:   :destroy

  has_many :trends, -> { order(date: :asc) },
           class_name:  "Package::Trend",
           primary_key: :name,
           foreign_key: :package_name,
           inverse_of:  :package,
           dependent:   :destroy

  has_many :package_dependencies,
           -> { order(dependency_name: :asc) },
           foreign_key: :package_name,
           inverse_of:  :package,
           dependent:   :destroy

  # Reverse dependencies of this package, so packages that use this one
  # as a dependency
  has_many :reverse_dependencies,
           -> { order(package_name: :asc) },
           class_name:  "PackageDependency",
           foreign_key: :dependency_name,
           inverse_of:  :dependency,
           dependent:   :destroy

  # The corresponding ruby toolbox project record for the corresponding
  # reverse dependency package
  has_many :reverse_dependency_projects,
           through:    :reverse_dependencies,
           source:     :depending_project,
           class_name: "Project"

  has_many :code_statistics,
           -> { order(language: :asc) },
           class_name:  "Package::CodeStatistic",
           foreign_key: :package_name,
           inverse_of:  :package,
           dependent:   :destroy

  scope :update_batch, lambda {
    where(fetched_at: ...24.hours.ago.utc)
      .order(fetched_at: :asc)
      .limit((count / 24.0).ceil)
  }

  def url
    File.join "https://packagist.org/packages", name
  end

  #
  # The supported laravel versions compressed into a readable label, i.e.
  # "11 – 13" for a contiguous range or "8, 11 – 13" when there are gaps.
  #
  def laravel_version_label
    return if laravel_versions.blank?

    laravel_versions.sort.slice_when { |previous, current| current > previous + 1 }.map do |run|
      run.one? ? run.first.to_s : "#{run.first} – #{run.last}"
    end.join(", ")
  end

  def supports_latest_laravel?
    laravel_versions.include? Laravel::LATEST_VERSION
  end
end
