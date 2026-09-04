# frozen_string_literal: true

require "rails_helper"

RSpec.describe Package::Advisory do
  fixtures :all

  subject(:model) { package_advisories(:nokogiri1) }

  it {
    expect(model).to belong_to(:package)
      .with_primary_key(:name)
      .with_foreign_key(:package_name)
      .inverse_of(:advisories)
  }

  it { expect(model).to validate_presence_of(:date) }
  it { expect(model).to validate_presence_of(:package_name) }

  %i[
    affected_versions
    cve
    remote_id
    reported_at
    severity
    source
    title
    url
  ].each do |property|
    it { is_expected.to delegate_method(property).to(:info) }
  end

  describe "#info" do
    subject(:info) { model.info }

    it { is_expected.to be_a(ApplicationStruct) }

    it do # rubocop:disable RSpec/ExampleLength
      expect(info).to have_attributes(
        identifier:        "PKSA-242x-7cm6-4w8j",
        package_name:      "nokogiri",
        remote_id:         "GHSA-242x-7cm6-4w8j",
        cve:               "CVE-2019-18197",
        url:               "https://github.com/advisories/GHSA-242x-7cm6-4w8j",
        reported_at:       Time.zone.parse("2022-05-24 09:12:44"),
        title:             "Use of Uninitialized Resource / Use After Free vulnerability",
        source:            "GitHub",
        severity:          "high",
        affected_versions: "<1.10.5"
      )
    end

    describe "for an advisory without an assigned CVE" do
      let(:model) { package_advisories :actionpack1 }

      it { expect(info).to have_attributes(cve: nil, severity: "medium") }
    end
  end

  describe ".from_packagist" do
    subject(:info) { described_class::Info.from_packagist advisory_data }

    let(:advisory_data) do
      {
        "advisoryId"  => "PKSA-1234-5678-9012",
        "packageName" => "laravel/framework",
        "reportedAt"  => "2026-06-17 13:54:13",
        "unknownKey"  => "is ignored",
      }
    end

    it "maps the upstream camelCase payload into our own naming" do
      expect(info).to have_attributes(identifier:   "PKSA-1234-5678-9012",
                                      package_name: "laravel/framework",
                                      reported_at:  Time.zone.parse("2026-06-17 13:54:13"),
                                      cve:          nil)
    end
  end
end
