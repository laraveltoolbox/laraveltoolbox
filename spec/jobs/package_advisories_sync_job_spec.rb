# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageAdvisoriesSyncJob do
  fixtures :all

  subject(:job) { described_class.new }

  let(:advisory_payload) do
    {
      "advisoryId"         => "PKSA-abcd-1234-efgh",
      "packageName"        => package_name,
      "remoteId"           => "GHSA-abcd-1234-efgh",
      "title"              => "Remote code execution via unserialized input",
      "link"               => "https://github.com/advisories/GHSA-abcd-1234-efgh",
      "cve"                => "CVE-2026-1234",
      "affectedVersions"   => "<1.2.3",
      "source"             => "GitHub",
      "reportedAt"         => "2026-02-01 13:54:13",
      "severity"           => "high",
      # Attributes we have no interest in are simply dropped
      "composerRepository" => "https://packagist.org",
      "sources"            => [{ "name" => "GitHub", "remoteId" => "GHSA-abcd-1234-efgh" }],
    }
  end

  let(:package_name) { "nokogiri" }

  describe ".import(advisory_data)" do
    subject(:import) { described_class.import advisory_payload }

    let(:advisory_count) do
      lambda do
        Package::Advisory.where(
          package_name:,
          identifier:   "PKSA-abcd-1234-efgh",
          date:         Date.new(2026, 2, 1)
        ).count
      end
    end

    it "persists the given advisory in the database" do
      expect { import }.to change(&advisory_count).from(0).to(1)
    end

    it { is_expected.to be_a Package::Advisory }

    it "stores the advisory details in our own naming" do
      expect(import.advisory_data).to include(
        "identifier"        => "PKSA-abcd-1234-efgh",
        "remote_id"         => "GHSA-abcd-1234-efgh",
        "url"               => "https://github.com/advisories/GHSA-abcd-1234-efgh",
        "cve"               => "CVE-2026-1234",
        "affected_versions" => "<1.2.3",
        "severity"          => "high"
      )
    end

    context "when the advisory already exists" do
      let!(:existing_advisory) do
        Package::Advisory.create! package_name:, identifier: "PKSA-abcd-1234-efgh", date: 3.years.ago
      end

      it { expect { import }.not_to change(Package::Advisory, :count) }

      it "updates the existing record in place" do
        import
        expect(existing_advisory.reload).to have_attributes(date:     Date.new(2026, 2, 1),
                                                            severity: "high")
      end
    end

    context "when the package is not in our database" do
      let(:package_name) { "very/unknown404" }

      it { is_expected.to eq :unknown_package }
      it { expect { import }.not_to change(Package::Advisory, :count) }
    end
  end

  describe "#perform" do
    subject(:perform) { job.perform }

    let(:advisories) { { package_name => [advisory_payload] } }

    before do
      allow(Packagist).to receive(:security_advisories).and_return advisories
      allow(described_class).to receive(:import).with(advisory_payload)
    end

    it { is_expected.to eq :complete }

    it "pulls the full advisory database" do
      perform
      expect(Packagist).to have_received(:security_advisories)
        .with(updated_since: described_class::FULL_SYNC_TIMESTAMP)
    end

    it "imports each advisory" do
      expect(described_class).to receive(:import).with(advisory_payload)
      perform
    end

    context "with an explicit sync timestamp" do
      subject(:perform) { job.perform 1_780_000_000 }

      it "only pulls advisories updated since then" do
        perform
        expect(Packagist).to have_received(:security_advisories)
          .with(updated_since: Time.zone.at(1_780_000_000))
      end
    end
  end
end
