# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackagesSyncJob do
  fixtures :all

  let(:job) { described_class.new }

  describe "#remote_packages" do
    before do
      allow(Packagist).to receive(:package_names)
        .with(type: "laravel-package")
        .and_return(%w[vendor/typed vendor/shared])

      allow(Packagist).to receive(:dependents).and_return(%w[vendor/dependent vendor/shared])
    end

    it "includes the packages published with the laravel-package type" do
      expect(job.remote_packages).to include "vendor/typed"
    end

    it "includes the dependents of the laravel core packages" do
      expect(job.remote_packages).to include "vendor/dependent"
    end

    it "fetches the most-downloaded dependents of each root package" do
      job.remote_packages

      described_class::ROOT_PACKAGES.each do |root_package|
        expect(Packagist).to have_received(:dependents)
          .with(root_package, max_pages: described_class::DEPENDENT_PAGES)
      end
    end

    it "does not report duplicates" do
      expect(job.remote_packages.count("vendor/shared")).to eq 1
    end

    it "includes packages referenced by the catalog" do
      category = Factories.category "Authentication"
      Factories.project("vendor/curated").update! categories: [category]

      expect(job.remote_packages).to include "vendor/curated"
    end
  end

  describe "#local_packages" do
    it "is a collection of names of locally mirrored packages" do
      allow(Package).to receive(:pluck).with(:name).and_return(%w[vendor/foo vendor/bar])
      expect(job.local_packages).to eq %w[vendor/foo vendor/bar]
    end
  end

  describe "#perform" do
    let(:local_packages)  { %w[vendor/known vendor/gone vendor/other] }
    let(:remote_packages) { %w[vendor/known vendor/fresh vendor/other] }

    before do
      allow(job).to receive_messages(local_packages:, remote_packages:)
    end

    it "triggers update jobs for all locally missing packages" do
      allow(PackageUpdateJob).to receive(:perform_async).with("vendor/gone")
      expect(PackageUpdateJob).to receive(:perform_async).with("vendor/fresh")
      job.perform
    end

    it "triggers update jobs for all remotely missing packages" do
      allow(PackageUpdateJob).to receive(:perform_async).with("vendor/fresh")
      expect(PackageUpdateJob).to receive(:perform_async).with("vendor/gone")
      job.perform
    end
  end
end
