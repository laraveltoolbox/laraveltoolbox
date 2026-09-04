# frozen_string_literal: true

require "rails_helper"

RSpec.describe Package::Advisory do
  fixtures :all

  subject(:model) { package_advisories(:laravel_framework1) }

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
        identifier:        "PKSA-w7xr-vk7n-rstm",
        package_name:      "laravel/framework",
        remote_id:         "laravel/framework/CVE-2024-52301.yaml",
        cve:               "CVE-2024-52301",
        url:               "https://github.com/advisories/GHSA-gv7v-rgg6-548h",
        reported_at:       Time.zone.parse("2024-11-12 15:29:00"),
        title:             "Laravel environment manipulation via query string",
        source:            "FriendsOfPHP/security-advisories",
        severity:          "high",
        affected_versions: "<6.20.45|>=7.0.0,<7.30.7|>=8.0.0,<8.83.28|>=9.0.0,<9.52.17|" \
                           ">=10.0.0,<10.48.23|>=11.0.0,<11.31.0"
      )
    end

    describe "for an advisory without an assigned CVE" do
      let(:model) { package_advisories :laravel_framework2 }

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
