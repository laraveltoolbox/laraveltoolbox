# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageDownloadsPersistenceJob, :clean_database do
  fixtures :all

  let(:job) { described_class.new }
  let(:do_perform) { job.perform }

  before do
    Package::DownloadStat.delete_all

    Factories.package "a", downloads: 100
    Factories.package "b", downloads: 200
    Factories.package "c", downloads: 300
  end

  def stats
    Package::DownloadStat.order(package_name: :asc, date: :asc).map do |stat|
      stat.attributes.symbolize_keys.slice(:package_name, :date, :total_downloads)
    end
  end

  describe "#should_run?" do
    it "is true on sundays" do
      Timecop.freeze Time.zone.today.end_of_week(:monday) do
        expect(job.should_run?).to be true
      end
    end

    it "is false on other days of the week" do
      # Any weekday other than sunday this week
      date = (Time.zone.today.beginning_of_week(:monday)...Time.zone.today.end_of_week(:sunday)).to_a.sample
      Timecop.freeze date do
        expect(job.should_run?).to be false
      end
    end
  end

  it "does not do anything if PackageDownloadsPersistenceJob.should_run? is false" do
    allow(job).to receive(:should_run?)
    expect { do_perform }.not_to change(Package::DownloadStat, :count).from(0)
  end

  describe "when no previous download stats exist" do
    before do
      allow(job).to receive(:should_run?).and_return(true)
    end

    it "creates the three expected download stat records" do
      expect { do_perform }.to change { stats }
        .from([])
        .to([
              { date: Time.zone.today, package_name: "a", total_downloads: 100 },
              { date: Time.zone.today, package_name: "b", total_downloads: 200 },
              { date: Time.zone.today, package_name: "c", total_downloads: 300 },
            ])
    end

    it "enqueues a PackageTrendsJob" do
      expect(PackageTrendsJob).to receive(:perform_async).with(Time.current.utc.to_date.to_s)
      do_perform
    end
  end

  describe "when previous stats do exist" do
    before do
      # Should not be changed
      Package.find("a").download_stats.create! date: "2019-02-03", total_downloads: 50

      # Should get updated
      Package.find("b").download_stats.create! date: Time.zone.today, total_downloads: 100

      allow(job).to receive(:should_run?).and_return(true)
    end

    it "performs expected upsert operation on records" do
      expect { do_perform }.to change { stats }
        .to([
              { date: Date.new(2019, 2, 3), package_name: "a", total_downloads: 50 },
              { date: Time.zone.today, package_name: "a", total_downloads: 100 },
              { date: Time.zone.today, package_name: "b", total_downloads: 200 },
              { date: Time.zone.today, package_name: "c", total_downloads: 300 },
            ])
    end

    it "enqueues a PackageTrendsJob" do
      expect(PackageTrendsJob).to receive(:perform_async).with(Time.current.utc.to_date.to_s)
      do_perform
    end
  end
end
