# frozen_string_literal: true

#
# The catalog tracks composer packages instead of rubygems, so the whole
# gem-flavoured schema is renamed to the neutral "package" terminology.
# Data is preserved, only names change.
#
class RenameRubygemsToPackages < ActiveRecord::Migration[8.1]
  TABLE_RENAMES = {
    rubygems:                :packages,
    rubygem_advisories:      :package_advisories,
    rubygem_code_statistics: :package_code_statistics,
    rubygem_dependencies:    :package_dependencies,
    rubygem_download_stats:  :package_download_stats,
    rubygem_trends:          :package_trends,
  }.freeze

  COLUMN_RENAMES = {
    projects:                :rubygem_name,
    package_advisories:      :rubygem_name,
    package_code_statistics: :rubygem_name,
    package_dependencies:    :rubygem_name,
    package_download_stats:  :rubygem_name,
    package_trends:          :rubygem_name,
  }.freeze

  # The gem-flavoured data is discarded and re-imported from packagist anyway,
  # so a plain rename is fine here despite strong_migrations' warning.
  def up
    safety_assured do
      up!
    end
  end

  def down
    safety_assured do
      down!
    end
  end

  private

  def up!
    drop_trigger :rubygem_stats_calculation_month, :rubygem_download_stats

    TABLE_RENAMES.each { |old_name, new_name| rename_table old_name, new_name }
    COLUMN_RENAMES.each { |table, column| rename_column table, column, :package_name }
    rename_column :package_trends, :rubygem_download_stat_id, :package_download_stat_id

    swap_project_parity_constraint from: "rubygem_name", to: "package_name"

    create_stats_trigger :month, 28
  end

  def down!
    drop_trigger :package_stats_calculation_month, :package_download_stats

    rename_column :package_trends, :package_download_stat_id, :rubygem_download_stat_id
    COLUMN_RENAMES.each { |table, column| rename_column table, :package_name, column }
    TABLE_RENAMES.each { |old_name, new_name| rename_table new_name, old_name }

    swap_project_parity_constraint from: "package_name", to: "rubygem_name"

    reversible_stats_trigger_for_rubygems
  end

  def swap_project_parity_constraint(from:, to:)
    execute "ALTER TABLE projects DROP CONSTRAINT check_project_permalink_and_#{from}_parity"
    execute <<~SQL.squish
      ALTER TABLE projects ADD CONSTRAINT check_project_permalink_and_#{to}_parity
        CHECK (((#{to} IS NULL) OR ((#{to})::text = (permalink)::text)))
    SQL
  end

  def create_stats_trigger(name, distance_in_days, table: :package_download_stats, column: :package_name,
                           trigger_prefix: "package")
    create_trigger("#{trigger_prefix}_stats_calculation_#{name}", compatibility: 1)
      .on(table)
      .declare("previous_downloads bigint; previous_relative_change decimal;")
      .before(:insert,
              :update,
              &difference_to_previous_trigger_sql(name, distance_in_days, table:, column:))
  end

  def reversible_stats_trigger_for_rubygems
    create_stats_trigger :month, 28,
                         table:          :rubygem_download_stats,
                         column:         :rubygem_name,
                         trigger_prefix: "rubygem"
  end

  def difference_to_previous_trigger_sql(name, distance_in_days, table:, column:)
    lambda do
      <<~SQL.squish
        SELECT total_downloads, relative_change_#{name} INTO previous_downloads, previous_relative_change
          FROM #{table}
          WHERE
            #{column} = NEW.#{column} AND date = NEW.date - #{distance_in_days};

        IF previous_downloads IS NOT NULL THEN
          NEW.absolute_change_#{name} := NEW.total_downloads - previous_downloads;
          IF previous_downloads > 0 THEN
            NEW.relative_change_#{name} := ROUND((NEW.absolute_change_#{name} * 100.0) / previous_downloads, 2);

            IF previous_relative_change IS NOT NULL THEN
              NEW.growth_change_#{name} := NEW.relative_change_#{name} - previous_relative_change;
            END IF;
          END IF;
        END IF;
      SQL
    end
  end
end
