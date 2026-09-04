# frozen_string_literal: true

#
# The category catalog is curated in https://github.com/laraveltoolbox/catalog
# and published to github pages from there, see `CatalogImportJob`.
#
# `db/catalog.json` is a local copy of that export, used as a fallback whenever
# no `CATALOG_URL` is configured (development, tests, offline setups).
#
module CatalogTasks
  def self.summary(catalog)
    groups = catalog.fetch("category_groups")
    categories = groups.flat_map { it.fetch("categories") }
    packages = categories.flat_map { it.fetch("projects") }.uniq

    "#{groups.count} groups, #{categories.count} categories, #{packages.count} packages"
  end
end

namespace :catalog do
  desc "Refresh db/catalog.json from the published catalog export"
  task pull: :environment do
    url = ENV.fetch("CATALOG_URL", CatalogImportJob::PUBLISHED_CATALOG_URL)
    response = HttpService.client.get url
    raise "Failed to fetch catalog from #{url}, response status was #{response.status}" unless response.status == 200

    catalog = JSON.parse response.to_s
    Rails.root.join(CatalogImportJob::LOCAL_CATALOG_PATH).write "#{JSON.pretty_generate(catalog)}\n"

    puts "Pulled #{CatalogTasks.summary(catalog)} from #{url}"
  end
end
