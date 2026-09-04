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
