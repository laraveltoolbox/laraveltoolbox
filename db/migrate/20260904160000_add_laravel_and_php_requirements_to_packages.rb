# frozen_string_literal: true

#
# The laravel and php versions a package supports are the first thing someone
# picking a package needs to know. Composer already carries that information in
# each release's `require` block, so we denormalize it onto the package for
# display and future filtering - see the Laravel model and Composer::Constraint.
#
# rubocop:disable Rails/BulkChangeTable -- strong_migrations cannot inspect a
# change_table block, and having it verify these columns is worth more than
# saving three ALTER statements on a one-off migration.
class AddLaravelAndPhpRequirementsToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :laravel_versions, :integer, array: true, default: [], null: false
    add_column :packages, :laravel_requirement, :string
    add_column :packages, :php_requirement, :string
    add_column :packages, :php_minimum_version, :string
  end
end
# rubocop:enable Rails/BulkChangeTable
