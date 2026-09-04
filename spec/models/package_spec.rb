# frozen_string_literal: true

require "rails_helper"

RSpec.describe Package do
  fixtures :all

  subject(:model) { described_class.new }

  describe "associations" do
    it { is_expected.to have_one(:project) }
    it { is_expected.to have_many(:advisories).order(date: :desc) }
    it { is_expected.to have_many(:download_stats).order(date: :asc) }
    it { is_expected.to have_many(:trends).order(date: :asc) }
    it { is_expected.to have_many(:package_dependencies).order(dependency_name: :asc).dependent(:destroy) }

    it "has_many package_dependencies" do
      expect(model).to have_many(:reverse_dependencies)
        .order(package_name: :asc)
        .dependent(:destroy)
    end

    it do
      expect(model).to have_many(:code_statistics)
        .order(language: :asc)
        .with_foreign_key(:package_name)
        .class_name("Package::CodeStatistic")
    end
  end

  describe ".update_batch" do
    subject(:scope) { described_class.update_batch.to_sql }

    let(:expected_sql) do
      described_class.where(fetched_at: ...24.hours.ago.utc)
                     .order(fetched_at: :asc)
                     .limit((described_class.count / 24.0).ceil)
                     .to_sql
    end

    around do |example|
      Timecop.freeze Time.current do
        example.run
      end
    end

    it { is_expected.to eq expected_sql }
  end

  describe "#url" do
    it "is derived from the package name" do
      expect(described_class.new(name: "spatie/laravel-permission").url)
        .to eq "https://packagist.org/packages/spatie/laravel-permission"
    end
  end

  describe "#laravel_version_label" do
    it "collapses a contiguous range" do
      expect(described_class.new(laravel_versions: [11, 12, 13]).laravel_version_label).to eq "11 – 13"
    end

    it "keeps a single version as is" do
      expect(described_class.new(laravel_versions: [13]).laravel_version_label).to eq "13"
    end

    it "spells out the runs when there are gaps" do
      expect(described_class.new(laravel_versions: [8, 11, 12, 13]).laravel_version_label).to eq "8, 11 – 13"
    end

    it "is blank for packages that do not depend on laravel" do
      expect(described_class.new(laravel_versions: []).laravel_version_label).to be_nil
    end
  end

  describe "#supports_latest_laravel?" do
    it "is true when the latest known laravel version is supported" do
      package = described_class.new laravel_versions: [Laravel::LATEST_VERSION]
      expect(package.supports_latest_laravel?).to be true
    end

    it "is false otherwise" do
      package = described_class.new laravel_versions: [Laravel::LATEST_VERSION - 1]
      expect(package.supports_latest_laravel?).to be false
    end
  end

  describe "#documentation_url" do
    it "is the package's documentation_url if set" do
      url = "https://laravel.com/docs"
      expect(described_class.new(documentation_url: url).documentation_url).to eq url
    end

    it "is blank when composer metadata carries no docs link" do
      expect(described_class.new(name: "spatie/laravel-permission").documentation_url).to be_nil
    end
  end
end
