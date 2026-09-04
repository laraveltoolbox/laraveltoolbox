# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageBackfillStatsJob do
  fixtures :all

  let(:package_name) { "spatie/laravel-permission" }
  let(:download_stats) { instance_double Package::DownloadStat.none.class }

  describe ".reconstructed_download_stats(package)" do
    subject(:stats) { described_class.reconstructed_download_stats package }

    let(:package) { instance_double Package, name: package_name, downloads: 1000 }
    # A week's worth of daily downloads, bracketed by two sundays
    let(:daily_downloads) do
      {
        Date.new(2026, 1,  4) => 1,
        Date.new(2026, 1,  5) => 2,
        Date.new(2026, 1,  6) => 3,
        Date.new(2026, 1,  7) => 4,
        Date.new(2026, 1,  8) => 5,
        Date.new(2026, 1,  9) => 6,
        Date.new(2026, 1, 10) => 7,
        Date.new(2026, 1, 11) => 8,
      }
    end

    before do
      allow(Packagist).to receive(:download_stats)
        .with(package_name, from: described_class::STATS_START_DATE)
        .and_return(daily_downloads)
    end

    it "walks the daily downloads backwards from the current all-time total" do
      expect(stats).to eq(
        Date.new(2026, 1, 11) => 1000,
        Date.new(2026, 1, 4)  => 965
      )
    end

    context "when the daily downloads exceed the reported all-time total" do
      let(:package) { instance_double Package, name: package_name, downloads: 5 }

      it "does not report negative totals" do
        expect(stats.values).to all(be >= 0)
      end
    end

    context "when packagist has no stats for the package" do
      let(:daily_downloads) { {} }

      it { is_expected.to eq({}) }
    end
  end

  describe ".missing_dates(package, available_dates)" do
    subject(:missing_dates) { described_class.missing_dates package, available_dates }

    let(:package) { instance_double Package, download_stats: }
    let(:available_dates) { Date.new(2025, 12, 7).step(Date.new(2026, 1, 11), 7).to_a }
    let(:expected_missing) { [Date.new(2025, 12, 28), Date.new(2026, 1, 4)] }

    before do
      allow(download_stats).to receive(:pluck).with(:date).and_return(available_dates - expected_missing)
    end

    it { is_expected.to eq expected_missing }

    context "when packagist reported no stats at all" do
      let(:available_dates) { [] }

      it { is_expected.to eq [] }
    end
  end

  describe "#perform" do
    subject(:perform) { described_class.new.perform package_name }

    let(:missing_dates) { [Date.new(2026, 1, 4)] }
    let(:reconstructed_stats) do
      {
        Date.new(2026, 1, 4)  => 965,
        Date.new(2026, 1, 11) => 1000,
      }
    end
    let(:package) do
      instance_double Package, name: package_name, download_stats:
    end

    let(:touch_scope) { instance_double Package::DownloadStat.none.class, update_all: nil }

    before do
      allow(Package).to receive(:find).with(package_name).and_return package
      allow(described_class).to receive(:reconstructed_download_stats).with(package).and_return reconstructed_stats
      allow(described_class).to receive(:missing_dates)
        .with(package, reconstructed_stats.keys.sort)
        .and_return missing_dates

      # Stub those as empty calls so we can safely run the code, and we will make individual expectations
      # in specific examples
      allow(package.download_stats).to receive(:create!)
      allow(package.download_stats).to receive(:where).with(absolute_change_month: nil).and_return(touch_scope)
    end

    it "returns the total number of created records" do
      expect(perform).to eq 1
    end

    it "creates the missing record" do
      expect(package.download_stats).to receive(:create!).with(
        date: Date.new(2026, 1, 4), total_downloads: 965
      )

      perform
    end

    it "causes the database triggers for relevant entries to fire" do
      expect(touch_scope).to receive(:update_all).with package_name: package.name

      perform
    end
  end
end
