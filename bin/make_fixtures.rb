# frozen_string_literal: true

require File.join(__dir__, "..", "config", "environment")

#
# This little script can be used to help with building new fixtures for the specs.
# You will need to have a production database dump loaded locally so realistic data
# to build the fixtures from is available - see bin/pull_database.
#

#
# The fixture projects deliberately avoid the package names used in
# config/http_mock_responses.yml: specs that exercise creating a package from
# scratch expect those to be absent from the database.
#
PROJECTS = %w[
  laravel/sanctum
  illuminate/support
  nunomaduro/collision
  larastan/larastan
  pestphp/pest
  laravel/docs
].freeze

# The one project whose readme is carried along, as they are rather large
README_PROJECT = "nunomaduro/collision"

EXCLUDED_COLUMNS = %w[
  fetched_at
  permalink_tsvector
  description_tsvector
  bugfix_fork_of
  bugfix_fork_criteria
  is_bugfix_fork
  name_tsvector
].freeze

def fixturify(model)
  model.attributes.as_json.except(*EXCLUDED_COLUMNS)
end

RESULTS = Hash.new { |hash, key| hash[key] = {} }
PROJECTS.each do |project_name|
  project = Project.find project_name

  RESULTS[:projects][project_name] = fixturify project

  if project.package
    RESULTS[:packages][project.package_name] = fixturify project.package
    project.package.package_dependencies.each do |dependency|
      RESULTS[:package_dependencies]["#{dependency.package_name}_#{dependency.dependency_name}"] =
        fixturify dependency
    end
  end
  RESULTS[:github_repos][project.github_repo_path] = fixturify project.github_repo if project.github_repo

  if project.permalink == README_PROJECT
    RESULTS[:github_readmes][project.github_repo_path] =
      fixturify project.github_repo_readme
  end

  project.categories.each do |category|
    RESULTS[:categories][category.permalink] = fixturify category
    RESULTS[:category_groups][category.category_group.permalink] = fixturify category.category_group
  end
end

RESULTS.each do |name, data|
  Rails.root.join("spec", "fixtures", "#{name}.yml").open("w+") do |f|
    f.puts "# Generated from realistic dataset using bin/make_fixtures.rb, please don't modify manually"
    f.puts data.to_yaml
  end
end
