# frozen_string_literal: true

#
# This class provides tooling for creating a selective database export
# into a compressed bundle of SQL files, one per table.
#
# Since the actual rubytoolbox database dump is quite large, it is
# quite slow to download and especially import into a fresh postgres
# database. This makes it not very suitable for a quick local development
# setup based on realistic data.
#
# Via this class, we can generate a smaller subset of data for quick
# local import.
#
# See also https://github.com/rubytoolbox/rubytoolbox/issues/1205
#
class Database::SelectiveExport
  module Scopes
    class << self
      def category_groups
        CategoryGroup.all
      end

      def categories
        Category.all
      end

      # All projects that have a category & any projects in top 1000 based on score
      def projects
        Project.where(permalink: Project.joins(:categories).distinct)
               .or(Project.where(permalink: Project.order(score: :desc).limit(1000)))
      end

      def categorizations
        Categorization.where project: projects
      end

      def packages
        Package.where project: projects
      end

      def package_download_stats
        # RADAR: Use select instead of pluck?
        Package::DownloadStat.where(package_name: packages.pluck(:name))
                             .where(date: 3.months.ago.to_date..)
                             .order(date: :asc)
      end

      def package_code_statistics
        Package::CodeStatistic.where package: packages
      end

      def package_dependencies
        PackageDependency.where package: packages, dependency: packages
      end

      def package_advisories
        Package::Advisory.where package: packages
      end

      def package_trends
        Package::Trend.where(package: packages).where(date: 1.month.ago.to_date..)
      end

      def github_repos
        GithubRepo.where(projects:)
      end

      # READMEs can be quite large, so we only do it for a smaller subset of projects
      def github_readmes
        Github::Readme.where github_repo: github_repos.limit(300).order(stargazers_count: :desc)
      end

      def github_ignores
        GithubIgnore.all
      end
    end
  end

  EXPORT_ORDER = %i[
    category_groups
    categories
    packages
    package_download_stats
    package_code_statistics
    package_dependencies
    package_trends
    package_advisories
    github_repos
    github_readmes
    github_ignores
    projects
    categorizations
  ].freeze

  #
  # Generates SQL bulk insert statements from the given ActiveRecord scope,
  # in batches and yields each statement i.e. for further processing into a file
  #
  def self.sql_inserts_from_scope(scope)
    scope.in_batches(of: 250).each do |batch|
      next if batch.empty?

      # This is a private API of ActiveRecord, however it's the easiest way to get this done -
      # an integration test should hopefully cover for potential future breaking changes.
      insert_all = ActiveRecord::InsertAll.new(
        batch,
        ApplicationRecord.connection,
        batch.map(&:attributes),
        on_duplicate: :skip
      ).send(:to_sql)
      # We're appending the semicolon as it's missing to form a proper SQL file with multiple statements.
      yield "#{insert_all};\n\n"
    end
  end

  def self.banner
    <<~BANNER
      /*
       *
       * ===== The Laravel Toolbox - Selective database export =====
       *
       * * https://www.laravel-toolbox.com
       * * https://github.com/laraveltoolbox/laraveltoolbox/
       *
       * This is a partial database export of the production data of the Laravel Toolbox,
       * intended for getting a development environment based on realistic data up & running
       * quickly without having to load the pretty massive full dataset, which can take several
       * hours to import.
       *
       + The latest export can be fetched from https://www.laravel-toolbox.com/database/exports/selective
       *
       * This export has been generated at #{Time.current.utc.iso8601}
       *
       */

    BANNER
  end

  def self.call # rubocop:disable Metrics/MethodLength
    Tempfile.create("export.sql.gz") do |file|
      Zlib::GzipWriter.open(file.path) do |gz|
        gz.write banner

        EXPORT_ORDER.each do |table_name|
          sql_inserts_from_scope Scopes.public_send(table_name) do |insert_sql|
            gz.write insert_sql
          end
        end
      end

      yield file
    end
  end
end
