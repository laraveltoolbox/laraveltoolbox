# frozen_string_literal: true

class Package::Advisory < ApplicationRecord
  #
  # A wrapper around the advisory payload as served by the packagist
  # security advisories API, see https://packagist.org/apidoc
  #
  class Info < ApplicationStruct
    # The upstream payload is camelCased, we store and expose it in the
    # ruby-flavoured naming instead
    ATTRIBUTE_MAPPING = {
      "advisoryId"       => :identifier,
      "packageName"      => :package_name,
      "remoteId"         => :remote_id,
      "title"            => :title,
      "link"             => :url,
      "cve"              => :cve,
      "affectedVersions" => :affected_versions,
      "source"           => :source,
      "severity"         => :severity,
      "reportedAt"       => :reported_at,
    }.freeze

    # Packagist reports timestamps in UTC without an offset, so they must not
    # be parsed in whatever timezone the machine happens to run in
    ReportedAt = Types::Strict::Time.constructor do |value|
      value.is_a?(String) ? Time.find_zone!("UTC").parse(value) : value
    end

    def self.from_packagist(advisory_data)
      new(ATTRIBUTE_MAPPING.to_h { |remote_key, local_key| [local_key, advisory_data[remote_key]] })
    end

    attribute :identifier, Types::Strict::String
    attribute :package_name, Types::Strict::String
    attribute :remote_id, Types::Strict::String.optional
    attribute :url, Types::Strict::String.optional
    attribute :title, Types::Strict::String.optional
    attribute :cve, Types::Strict::String.optional
    # Composer version constraints of the affected releases, e.g. `<12.61.1|>=13.0.0,<13.12.0`
    attribute :affected_versions, Types::Strict::String.optional
    attribute :source, Types::Strict::String.optional
    attribute :severity, Types::Strict::String.optional
    attribute :reported_at, ReportedAt
  end

  belongs_to :package,
             primary_key: :name,
             foreign_key: :package_name,
             inverse_of:  :advisories

  validates :date, presence: true
  validates :package_name, presence: true

  # `identifier` and `package_name` are columns on this record already
  delegate(*Package::Advisory::Info.instance_methods(false).excluding(:identifier, :package_name), to: :info)

  def info
    # If the underlying data changes, the info struct would get stale,
    # but that's fine because normally this data is updated out-of-band in the
    # advisory sync job, so no need for adding complex memo busting logic
    @info ||= Info.new advisory_data
  end
end
