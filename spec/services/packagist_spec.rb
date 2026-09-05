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

    #
    # The p2 mirror only spells out the fields that changed since the previous
    # release, so without expanding them every release but the newest would
    # look like it has no requirements, license or support urls at all.
    #
    it "expands the fields inherited from the previous release" do
      expect(versions.pluck("require")).to all eq(
        "php" => "^8.2", "illuminate/auth" => "^10.0|^11.0", "illuminate/container" => "^10.0|^11.0"
      )
    end

    it "drops fields the minified format marks as unset" do
      allow(described_class).to receive(:get).and_return(
        "minified" => "composer/2.0",
        "packages" => {
          package_name => [
            { "version" => "2.0.0", "require" => { "php" => "^8.2" }, "homepage" => "https://example.com" },
            { "version" => "1.0.0", "homepage" => "__unset" },
          ],
        }
      )

      expect(versions.pluck("homepage")).to eq ["https://example.com", nil]
    end

    context "when the response is not minified" do
      it "returns the releases untouched" do
        allow(described_class).to receive(:get).and_return(
          "packages" => { package_name => [{ "version" => "1.0.0" }] }
        )

        expect(versions).to eq [{ "version" => "1.0.0" }]
      end
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

    #
    # A full crawl is hundreds of sequential requests, so a transient failure
    # somewhere in the middle is expected. Aborting would discard all the pages
    # already walked, since the retried job starts over from the first one.
    #
    context "when a page fails for a reason that tends to pass" do
      before { allow(described_class).to receive(:sleep) }

      def fail_first_request_with(error)
        failed = false

        allow(described_class).to receive(:get).and_wrap_original do |original, *args, **kwargs|
          next original.call(*args, **kwargs) if failed

          failed = true
          raise error
        end
      end

      it "retries a throttled request and completes the crawl" do
        fail_first_request_with described_class::InvalidResponse.new("https://packagist.org", 429)

        expect(dependents).to eq %w[vendor/first vendor/second vendor/third]
      end

      it "retries a server error and completes the crawl" do
        fail_first_request_with described_class::InvalidResponse.new("https://packagist.org", 503)

        expect(dependents).to eq %w[vendor/first vendor/second vendor/third]
      end

      it "retries a network level failure and completes the crawl" do
        fail_first_request_with HTTP::TimeoutError.new("execution expired")

        expect(dependents).to eq %w[vendor/first vendor/second vendor/third]
      end
    end

    #
    # Returning the pages collected so far would be read as the missing
    # packages having disappeared from packagist
    #
    context "when a page keeps failing" do
      let(:delays) { [] }

      before do
        allow(described_class).to receive(:sleep) { |delay| delays << delay }
        allow(described_class).to receive(:get)
          .and_raise(described_class::InvalidResponse.new("https://packagist.org", 503))
      end

      it "gives up rather than returning a truncated list" do
        expect { dependents }.to raise_error described_class::InvalidResponse, /status=503/
      end

      it "stops after the configured number of attempts" do
        suppress(described_class::InvalidResponse) { dependents }

        expect(described_class).to have_received(:get).exactly(described_class::REQUEST_ATTEMPTS).times
      end

      it "backs off further with every attempt" do
        suppress(described_class::InvalidResponse) { dependents }

        expect(delays).to eq [2, 4, 8, 16]
      end
    end

    #
    # A rejected request stays rejected, so spending the full retry budget on
    # it only delays surfacing the problem
    #
    context "when a page fails for a reason that will not pass" do
      before do
        allow(described_class).to receive(:sleep)
        allow(described_class).to receive(:get)
          .and_raise(described_class::InvalidResponse.new("https://packagist.org", 403))
      end

      it "surfaces the error" do
        expect { dependents }.to raise_error described_class::InvalidResponse, /status=403/
      end

      it "does not retry" do
        suppress(described_class::InvalidResponse) { dependents }

        expect(described_class).to have_received(:get).once
      end
    end
  end
end
