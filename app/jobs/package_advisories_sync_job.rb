# frozen_string_literal: true

#
# Syncs the security advisories packagist.org publishes for composer
# packages into our own `Package::Advisory` model.
#
# The upstream data originates from the FriendsOfPHP security advisories
# database and GitHub's advisory database, see
# https://packagist.org/apidoc for details.
#
class PackageAdvisoriesSyncJob < ApplicationJob
  # The full advisory dump is a couple of megabytes only, so we always pull
  # everything instead of tracking sync state - this way packages that entered
  # the mirror later get their historical advisories too
  FULL_SYNC_TIMESTAMP = Time.zone.at(1)

  def self.import(advisory_data)
    info = Package::Advisory::Info.from_packagist advisory_data

    return :unknown_package unless Package.exists?(name: info.package_name)

    Package::Advisory.find_or_initialize_by(package_name: info.package_name, identifier: info.identifier)
                     .tap do |record|
      record.update! date: info.reported_at.to_date, advisory_data: info.to_h
    end
  end

  delegate :import, to: :class

  def perform(updated_since = nil)
    updated_since = updated_since ? Time.zone.at(updated_since.to_i) : FULL_SYNC_TIMESTAMP

    Packagist.security_advisories(updated_since:).each_value do |advisories|
      advisories.each { import it }
    end

    :complete
  end
end
