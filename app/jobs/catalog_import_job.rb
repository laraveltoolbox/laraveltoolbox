# frozen_string_literal: true

#
# Imports the category catalog, which is curated in the separate
# https://github.com/laraveltoolbox/catalog repository and published to github
# pages from there. Production points `CATALOG_URL` at that export.
#
# Without `CATALOG_URL` the import falls back to the copy checked into this repo
# at `db/catalog.json`, which `rake catalog:pull` refreshes.
#
class CatalogImportJob < ApplicationJob
  sidekiq_options queue: :priority

  LOCAL_CATALOG_PATH = "db/catalog.json"

  # Where the curated catalog repository publishes its export. Production points
  # `CATALOG_URL` here, `rake catalog:pull` refreshes the local copy from it.
  PUBLISHED_CATALOG_URL = "https://laraveltoolbox.github.io/catalog/catalog.json"

  def perform
    CatalogImport.perform catalog_data

    CategoryRankingJob.perform_async
  end

  def catalog_data
    catalog_url.present? ? remote_catalog : local_catalog
  end

  def catalog_url
    ENV.fetch("CATALOG_URL", nil)
  end

  def http_client
    @http_client ||= HttpService.client
  end

  private

  def remote_catalog
    response = http_client.get catalog_url
    raise "Failed to fetch catalog, response status was #{response.status}" unless response.status == 200

    JSON.parse response.body
  end

  def local_catalog
    JSON.parse Rails.root.join(LOCAL_CATALOG_PATH).read
  end
end
