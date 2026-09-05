# frozen_string_literal: true

#
# Thin wrapper around the packagist.org APIs we consume, see
# https://packagist.org/apidoc for the upstream documentation.
#
# Package metadata is read from the static repo.packagist.org mirror where
# possible since it is CDN-cached and does not carry the rate limits of the
# main site's API.
#
module Packagist
  BASE_URL = "https://packagist.org"
  REPO_URL = "https://repo.packagist.org"

  # Platform requirements like `php`, `ext-json` or `lib-openssl` are not
  # actual packages and are skipped when syncing dependencies
  PLATFORM_REQUIREMENT = /\A(php(-64bit|-ipv6|-zts|-debug)?|hhvm|ext-.+|lib-.+|composer(-.+)?)\z/i

  # The advisory dump weighs in at several megabytes, so it needs more headroom
  # than the small json documents the other endpoints return
  ADVISORIES_READ_TIMEOUT = 30

  # The format the p2 mirror serves release metadata in, see
  # https://github.com/composer/composer/blob/main/src/Composer/MetadataMinifier/MetadataMinifier.php
  MINIFIED_FORMAT = "composer/2.0"

  # Marks a field as removed rather than inherited in the minified format
  UNSET_MARKER = "__unset"

  class InvalidResponse < StandardError
    attr_reader :status, :url

    def initialize(url, status)
      @url = url
      @status = status
      super("Unexpected response status=#{status} for url=#{url}")
    end
  end

  class << self
    #
    # The aggregated package information (downloads, favers, dependent counts,
    # github metrics). Returns nil when packagist does not know the package.
    #
    def package(name)
      get(File.join(BASE_URL, "packages", "#{name}.json"))&.fetch("package", nil)
    end

    #
    # All tagged releases of the package, newest first. Returns nil when
    # packagist does not know the package.
    #
    # The p2 mirror serves this in composer's minified format, where each entry
    # only carries the fields that changed relative to the previous one - so the
    # releases are expanded back into standalone documents before returning.
    #
    def versions(name)
      data = get File.join(REPO_URL, "p2", "#{name}.json")
      versions = data&.dig("packages", name)
      return versions unless versions && data["minified"] == MINIFIED_FORMAT

      expand versions
    end

    #
    # Daily download counts as a `Date => Integer` hash. Note that unlike the
    # aggregate `downloads.total` these are per-day numbers, not running totals.
    #
    def download_stats(name, from:)
      url = "#{File.join(BASE_URL, 'packages', name, 'stats', 'all.json')}?average=daily&from=#{from.to_fs(:db)}"
      data = get(url)
      return {} unless data

      labels = data.fetch("labels", [])
      values = data.fetch("values", {}).values.first || []

      labels.zip(values).to_h { |label, value| [Date.parse(label), value.to_i] }
    end

    #
    # All security advisories updated since the given time, as a
    # `package name => [advisory data]` hash.
    #
    def security_advisories(updated_since:)
      data = get "#{BASE_URL}/api/security-advisories/?updatedSince=#{updated_since.to_i}",
                 read_timeout: ADVISORIES_READ_TIMEOUT
      data&.fetch("advisories", nil) || {}
    end

    #
    # All package names of the given composer type, e.g. `laravel-package`
    #
    def package_names(type:)
      data = get("#{BASE_URL}/packages/list.json?type=#{type}")
      data&.fetch("packageNames", nil) || []
    end

    #
    # The names of packages depending on the given package.
    #
    # Ordered by name rather than by downloads: the list is walked in full, and
    # download counts shift while the crawl is running, which moves packages
    # across page boundaries and would silently drop them.
    #
    def dependents(name, max_pages: 1)
      url = "#{File.join(BASE_URL, 'packages', name, 'dependents.json')}?order_by=name"

      max_pages.times.each_with_object([]) do |_page, names|
        data = get(url)
        break names unless data

        names.concat data.fetch("packages", []).pluck("name")

        url = data["next"]
        break names unless url
      end
    end

    private

    #
    # Rebuilds standalone release documents from composer's minified format:
    # every entry inherits the previous one's fields, overriding those it names
    # itself and dropping those it marks as unset.
    #
    def expand(versions)
      inherited = nil

      versions.map do |version|
        inherited = if inherited
                      unset = version.select { |_, value| value == UNSET_MARKER }.keys
                      inherited.merge(version).except(*unset)
                    else
                      version
                    end
      end
    end

    def get(url, read_timeout: HttpService::DEFAULT_READ_TIMEOUT)
      response = HttpService.client(read_timeout:).get url

      return nil if response.status == 404
      raise InvalidResponse.new(url, response.status.to_i) unless response.status == 200

      Oj.load response.to_s
    end
  end
end
