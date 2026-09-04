# frozen_string_literal: true

#
# Retrieves and persists lines of code statistics for given package name
#
class PackageCodeStatsJob < ApplicationJob
  def perform(package_name)
    package = Package.find package_name

    # Packages that are not hosted on github cannot be measured
    statistics = fetch_stats(package) or return :unknown_source

    statistics.each do |statistic|
      package.code_statistics.find_or_initialize_by(language: statistic.language).update!(
        blanks:   statistic.blanks,
        code:     statistic.code,
        comments: statistic.comments
      )
    end

    package.code_statistics.where.not(language: statistics.map(&:language)).destroy_all
  end

  private

  def fetch_stats(package)
    PackageCodeStatsService.statistics name: package.name, version: package.current_version
  rescue PackageCodeStatsService::UnknownSourceError => e
    Rails.logger.info "Skipping code statistics for #{package.name}: #{e.message}"
    nil
  end
end
