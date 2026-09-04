# frozen_string_literal: true

require "rails_helper"

RSpec.describe Packagist do
  let(:package_name) { "spatie/laravel-permission" }

  describe ".package" do
    subject(:package) { described_class.package package_name }

    it "returns the aggregated package information" do
      expect(package).to include("name" => package_name, "dependents" => 1234)
    end

    context "when packagist does not know the package" do
      let(:package_name) { "unknown/package" }

      it { is_expected.to be_nil }
    end

    context "when packagist is down" do
      let(:package_name) { "downinmock/package" }

      it { expect { package }.to raise_error described_class::InvalidResponse, /status=500/ }
    end
  end

  describe ".versions" do
    subject(:versions) { described_class.versions package_name }

    it "returns all tagged releases" do
      expect(versions.pluck("version")).to eq %w[6.10.1 6.10.0 6.0.0-beta1 1.0.0]
    end

    context "when packagist does not know the package" do
      let(:package_name) { "unknown/package" }

      it { is_expected.to be_nil }
    end
  end

  describe ".download_stats" do
    subject(:download_stats) { described_class.download_stats package_name, from: Date.new(2026, 1, 4) }

    it "returns the daily download counts by date" do
      expect(download_stats).to eq(
        Date.new(2026, 1, 4) => 10,
        Date.new(2026, 1, 5) => 20,
        Date.new(2026, 1, 6) => 30
      )
    end

    context "when packagist has no stats for the package" do
      let(:package_name) { "unknown/package" }

      it { is_expected.to eq({}) }
    end
  end

  describe ".security_advisories" do
    subject(:advisories) { described_class.security_advisories updated_since: Time.zone.at(1) }

    it "returns the advisories by package name" do
      expect(advisories.fetch(package_name).first).to include "advisoryId" => "PKSA-abcd-1234-efgh"
    end

    context "when the advisory database is unavailable" do
      subject(:advisories) { described_class.security_advisories updated_since: Time.zone.at(2) }

      it { is_expected.to eq({}) }
    end
  end

  describe ".package_names" do
    subject(:package_names) { described_class.package_names type: "laravel-package" }

    it { is_expected.to eq %w[vendor/laravel-thing vendor/other] }

    context "with an unknown composer type" do
      subject(:package_names) { described_class.package_names type: "unknown-type" }

      it { is_expected.to eq [] }
    end
  end

  describe ".dependents" do
    subject(:dependents) { described_class.dependents "laravel/framework", max_pages: 5 }

    it "follows the pagination until the last page" do
      expect(dependents).to eq %w[vendor/first vendor/second vendor/third]
    end

    context "when fewer pages are requested than available" do
      subject(:dependents) { described_class.dependents "laravel/framework", max_pages: 1 }

      it { is_expected.to eq %w[vendor/first vendor/second] }
    end

    context "when the package is unknown" do
      subject(:dependents) { described_class.dependents "unknown/package", max_pages: 5 }

      it { is_expected.to eq [] }
    end
  end
end
