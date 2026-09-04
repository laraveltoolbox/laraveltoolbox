# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageCodeStatsService, type: :service do
  let(:service) { described_class.new(name:, version:) }
  let(:name) { "spatie/laravel-permission" }
  let(:version) { "6.10.1" }
  let(:reference) { "9d24aca7e6b4b0f0a04eebd9e0b46a1eb1b23a8f" }
  let(:source) { { "url" => "https://github.com/spatie/laravel-permission.git", "reference" => reference } }
  let(:archive) { file_fixture "laravel-package-source.tar.gz" }

  before do
    allow(Packagist).to receive(:versions)
      .with(name)
      .and_return([{ "version" => "6.10.0", "source" => source },
                   { "version" => "6.10.1", "source" => source }])
  end

  describe ".statistics" do
    subject(:statistics) { described_class.statistics name:, version: }

    let(:instance) do
      instance_double described_class, statistics: SecureRandom.hex(5)
    end

    before do
      allow(described_class).to receive(:new)
        .with(name:, version:)
        .and_return instance
    end

    it { is_expected.to be instance.statistics }
  end

  describe "#archive_url" do
    subject(:archive_url) { service.archive_url }

    it { is_expected.to eq "https://codeload.github.com/spatie/laravel-permission/tar.gz/#{reference}" }

    context "when packagist does not know the requested version" do
      let(:version) { "1.2.3" }

      it { expect { archive_url }.to raise_error described_class::UnknownSourceError, /no version/ }
    end

    context "when the package is not hosted on github" do
      let(:source) { { "url" => "https://gitlab.com/spatie/laravel-permission.git", "reference" => reference } }

      it { expect { archive_url }.to raise_error described_class::UnknownSourceError, /github/ }
    end

    context "when the release carries no source reference" do
      let(:source) { { "url" => "https://github.com/spatie/laravel-permission.git", "reference" => nil } }

      it { expect { archive_url }.to raise_error described_class::UnknownSourceError, /source reference/ }
    end
  end

  describe "#statistics" do
    subject(:statistics) { service.statistics }

    before do
      stub_request(:get, service.archive_url)
        .to_return(status: 200, body: archive.read)
    end

    it { is_expected.to be_a(described_class::ResultSet).and have_attributes(count: 3) }

    it do # rubocop:disable RSpec/ExampleLength -- Since extraction is a bit expensive better verify in one swoop
      expect(statistics).to include(
        have_attributes(
          language: "php",
          blanks:   7,
          code:     28,
          comments: 5
        )
      ).and include(
        have_attributes(
          language: "markdown",
          code:     0,
          comments: 5
        )
      ).and include(
        # Tokei reports "JavaScript", which the result set normalizes
        have_attributes(
          language: "java_script",
          code:     4,
          comments: 1
        )
      )
    end

    context "when the archive cannot be downloaded" do
      before do
        stub_request(:get, service.archive_url).to_return(status: 500)
      end

      it { expect { statistics }.to raise_error(/Unknown response/) }
    end
  end
end
