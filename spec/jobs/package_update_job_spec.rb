# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageUpdateJob do
  fixtures :all

  let(:job) { described_class.new }
  let(:do_perform) { job.perform package_name }
  let(:package_name) { "spatie/laravel-permission" }

  describe "#perform" do
    let(:expected_attributes) do
      {
        authors:                    "Freek Van der Herten, Spatie",
        bug_tracker_url:            "https://github.com/spatie/laravel-permission/issues",
        current_version:            "6.10.1",
        description:                "Permission handling for Laravel 8.0 and up",
        documentation_url:          "https://spatie.be/docs/laravel-permission",
        downloads:                  114_204_067,
        homepage_url:               "https://spatie.be/docs/laravel-permission",
        licenses:                   %w[MIT],
        mailing_list_url:           nil,
        name:                       "spatie/laravel-permission",
        source_code_url:            "https://github.com/spatie/laravel-permission.git",
        wiki_url:                   nil,
        first_release_on:           Date.new(2015, 7, 24),
        latest_release_on:          Date.new(2026, 2, 1),
        releases_count:             4,
        reverse_dependencies_count: 1234,
      }
    end

    it "applies the remote info attributes" do
      do_perform

      expect(Package.find(package_name)).to have_attributes(expected_attributes)
    end

    it "ignores unstable releases when picking the current version" do
      do_perform

      expect(Package.find(package_name).current_version).to eq "6.10.1"
    end

    it "changes the updated_at timestamp regardless of changes" do
      described_class.new.perform package_name
      Package.find(package_name).update! updated_at: 2.days.ago
      expect { do_perform }.to(change { Package.find(package_name).updated_at })
    end

    it do
      expect(ProjectUpdateJob).to receive(:perform_async).with(package_name)
      do_perform
    end

    it do
      expect(PackageCodeStatsJob).to receive(:perform_async).with(package_name)
      do_perform
    end

    context "when current_version didn't change during update" do
      before do
        Factories.package(package_name).tap { it.update! current_version: expected_attributes.fetch(:current_version) }
      end

      it do
        expect(PackageCodeStatsJob).not_to receive(:perform_async)
        do_perform
      end
    end

    it "stores quarterly release counts" do
      do_perform
      expected = { "2015-3" => 1, "2025-4" => 2, "2026-1" => 1 }
      expect(Package.find(package_name).quarterly_release_counts).to eq expected
    end

    describe "dependencies" do
      it "persists package dependencies" do
        do_perform
        dependencies = Package.find(package_name)
                              .package_dependencies
                              .pluck(:dependency_name, :type, :requirements)

        expect(dependencies).to eq [
          ["illuminate/auth", "runtime", "^10.0|^11.0"],
          ["illuminate/container", "runtime", "^10.0|^11.0"],
          ["orchestra/testbench", "development", "^8.0"],
          ["phpunit/phpunit", "development", "^10.1"],
        ]
      end

      it "skips platform requirements like php itself" do
        do_perform

        expect(Package.find(package_name).package_dependencies.pluck(:dependency_name)).not_to include "php"
      end

      it "drops obsolete dependencies" do
        described_class.new.perform package_name
        PackageDependency.create! package_name:,
                                  dependency_name: "old/package",
                                  requirements:    "^0.1.0",
                                  type:            "development"

        expect { do_perform }.to change { Package.find(package_name).package_dependencies.pluck(:dependency_name) }
          .to(["illuminate/auth", "illuminate/container", "orchestra/testbench", "phpunit/phpunit"])
      end
    end

    describe "when the package never cut a stable release" do
      let(:package_name) { "vendor/dev-only" }

      it "falls back to the unstable release" do
        do_perform

        expect(Package.find(package_name)).to have_attributes(current_version: "dev-main",
                                                              releases_count:  1)
      end
    end

    describe "when the package is unknown to packagist" do
      let(:package_name) { "unknown/package" }

      before { Factories.package package_name }

      it "drops the local package record" do
        expect { do_perform }.to change { Package.exists?(name: package_name) }.from(true).to(false)
      end
    end

    describe "when packagist is down" do
      let(:package_name) { "downinmock/package" }

      it "raises an exception" do
        expect { do_perform }.to raise_error Packagist::InvalidResponse, /status=500/
      end
    end
  end
end
