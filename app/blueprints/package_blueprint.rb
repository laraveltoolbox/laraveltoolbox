# frozen_string_literal: true

class PackageBlueprint < ApplicationBlueprint
  identifier :name

  fields :current_version,
         :first_release_on,
         :latest_release_on,
         :licenses,
         :url

  field :compatibility do |package|
    {
      laravel_versions:    package.laravel_versions,
      laravel_requirement: package.laravel_requirement,
      php_minimum_version: package.php_minimum_version,
      php_requirement:     package.php_requirement,
    }
  end

  field :stats do |package|
    {
      downloads:                  package.downloads,
      reverse_dependencies_count: package.reverse_dependencies_count,
      quarterly_release_counts:   package.quarterly_release_counts,
      releases_count:             package.releases_count,
    }
  end
end
