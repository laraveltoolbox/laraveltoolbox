# frozen_string_literal: true

#
# A simple HTTP client for interacting with [MeiliSearch](https://www.meilisearch.com/)
#
class MeiliSearch
  class UnknownResponseStatus < StandardError
    def initialize(response)
      super("Received unexpected response status #{response.status}")
    end
  end

  #
  # Returns an instance configured from MEILI_SEARCH_URL
  # environment variable, or nil if that is not set.
  #
  # MEILI_SEARCH_KEY carries the api key meilisearch expects as a bearer
  # token. It is optional: an instance started without a master key, or one
  # reached through a proxy that authenticates for us, needs no key.
  #
  def self.client
    return if ENV["MEILI_SEARCH_URL"].blank?

    new url: ENV["MEILI_SEARCH_URL"].presence, api_key: ENV["MEILI_SEARCH_KEY"].presence
  end

  attr_accessor :http
  private :http=

  def initialize(url:, api_key: nil)
    self.http = prepare_http_client URI.parse(url), api_key
  end

  def search(index, query)
    response = http.post "/indexes/#{index}/search", json: { q: query, limit: 1000 }
    raise UnknownResponseStatus, response unless response.status == 200

    Oj.load(response).fetch("hits").map { it.fetch("permalink") }
  end

  def ranking_rules(index)
    settings(index).fetch("rankingRules")
  end

  def searchable_attributes(index)
    settings(index).fetch("searchableAttributes")
  end

  def displayed_attributes(index)
    settings(index).fetch("displayedAttributes")
  end

  def store_documents(index, documents)
    queue_index_update index, :documents, documents
  end

  def update_ranking_rules(index, rules)
    queue_index_update index, "settings/ranking-rules", rules
  end

  def update_searchable_attributes(index, attributes)
    queue_index_update index, "settings/searchable-attributes", attributes
  end

  def update_displayed_attributes(index, attributes)
    queue_index_update index, "settings/displayed-attributes", attributes
  end

  private

  def settings(index)
    response = http.get "/indexes/#{index}/settings"
    raise UnknownResponseStatus, response unless response.status == 200

    Oj.load response.body
  end

  def prepare_http_client(uri, api_key = nil)
    client = HTTP
             .persistent(persistent_origin(uri))
             .timeout(connect: 2.seconds, write: 2.seconds, read: 2.seconds)

    return client.auth("Bearer #{api_key}") if api_key.present?
    return client.basic_auth(user: uri.user, pass: uri.password) if [uri.user, uri.password].any?

    client
  end

  #
  # The origin every request is issued against. A non-default port has to be
  # part of it: meilisearch listens on 7700, and dropping the port here would
  # send every request to 80 instead.
  #
  def persistent_origin(uri)
    host = uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"

    "#{uri.scheme}://#{host}"
  end

  def queue_index_update(index, path, data) # rubocop:disable Naming/PredicateMethod -- not a predicate
    response = http.post "/indexes/#{index}/#{path}", json: data
    response.body.to_s
    raise UnknownResponseStatus, response unless response.status == 202

    true
  end
end
