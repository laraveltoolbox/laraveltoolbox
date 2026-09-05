# frozen_string_literal: true

#
# This class downloads and extracts the source archive for a given
# composer package name and version, runs it through Tokei code statistics
# and returns the results wrapped in the ResultSet for convenience
#
# Unlike rubygems, packagist does not host the package contents itself, it
# only references the source repository and the exact commit a release was
# cut from. We therefore fetch the tarball straight from github.
#
class PackageCodeStatsService
  class UnknownSourceError < StandardError; end

  #
  # Raised when the archive is retrievable in principle but this particular
  # request did not work out, i.e. throttling or a gateway error. Unlike
  # `UnknownSourceError` this is worth another attempt, so it is left to fail
  # the job and let sidekiq retry it.
  #
  class DownloadError < StandardError; end

  class ResultSet
    class Entry
      attr_accessor :language, :blanks, :code, :comments

      def initialize(language, stats)
        self.language = language.tr(" ", "_").underscore
        self.blanks = stats.fetch("blanks")
        self.code = stats.fetch("code")
        self.comments = stats.fetch("comments")
      end
    end

    private attr_accessor :results
    delegate :each, to: :results
    include Enumerable

    def initialize(tokei_json_output)
      self.results = tokei_json_output.except("Total").map do |language, stats|
        Entry.new language, stats
      end
    end
  end

  def self.statistics(name:, version:)
    new(name:, version:).statistics
  end

  delegate :logger, to: :Rails

  private attr_accessor :name, :version

  def initialize(name:, version:)
    self.name = name
    self.version = version
  end

  def statistics
    with_extracted_package do |extracted_path|
      ResultSet.new Tokei.new.stats(extracted_path)
    end
  end

  #
  # The github tarball for the exact commit the release was tagged from.
  # Codeload serves these without any api rate limiting.
  #
  def archive_url
    File.join "https://codeload.github.com", repository_path, "tar.gz", source_reference
  end

  private

  def release
    @release ||= Array(Packagist.versions(name)).find { it["version"] == version } ||
                 raise(UnknownSourceError, "packagist knows no version #{version} of #{name}")
  end

  def repository_path
    @repository_path ||= Github.detect_repo_name(release.dig("source", "url").to_s) ||
                         raise(UnknownSourceError, "#{name} #{version} has no github source repository")
  end

  def source_reference
    @source_reference ||= release.dig("source", "reference").presence ||
                          raise(UnknownSourceError, "#{name} #{version} has no source reference")
  end

  def with_extracted_package
    Dir.mktmpdir do |path|
      yield extract_archive download_archive_into(path)
    end
  end

  def filename
    "#{name.tr('/', '-')}-#{version}.tar.gz"
  end

  def download_archive_into(directory)
    destination_path = Pathname.new(directory).join filename
    logger.info "Downloading package #{name} #{version} into #{destination_path}"

    download! archive_url, to: destination_path

    logger.info "Package written into #{destination_path}"

    destination_path
  end

  def extract_archive(archive_path)
    destination = Pathname.new(archive_path).dirname.join("extracted")
    logger.info "Extracting #{File.basename(archive_path)} to #{destination}"

    reader = Zlib::GzipReader.new File.open(archive_path, "rb")
    Minitar.unpack reader, destination.to_s

    destination
  end

  #
  # A 404 from codeload means the archive is not coming back: the repository
  # was deleted, renamed away without a redirect or turned private, or the
  # commit the release was tagged from no longer exists. Retrying that for
  # three weeks achieves nothing, so it is reported as a missing source and the
  # package is simply left without code statistics until its next release
  # points at a reachable commit.
  #
  def download!(source_url, to:)
    response = HTTP.follow.get source_url

    raise UnknownSourceError, "#{name} #{version} is no longer available at #{source_url}" if
      response.status.not_found?
    raise DownloadError, "Unexpected response #{response.status} for #{source_url}" unless response.status.ok?

    Pathname.new(to).open "wb+" do |f|
      f.print response.body.to_s
    end
  end
end
