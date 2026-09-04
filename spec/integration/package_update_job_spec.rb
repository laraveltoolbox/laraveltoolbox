# frozen_string_literal: true

require "rails_helper"

RSpec.describe PackageUpdateJob, :real_http do
  fixtures :all

  let(:job) { described_class.new }
  let(:do_perform) { job.perform package_name }

  describe "for an existing package", vcr: { cassette_name: :packagist_package } do
    let(:package_name) { "spatie/laravel-permission" }

    shared_examples_for "a package data update" do
      it "stores the data locally" do
        do_perform
        expect(Package.find(package_name)).to have_attributes(
          description:                kind_of(String),
          downloads:                  (a_value > 1_000_000),
          first_release_on:           (a_value > Date.new(2015, 1, 1)),
          latest_release_on:          (a_value > Date.new(2020, 1, 1)),
          reverse_dependencies_count: (a_value > 50),
          releases_count:             (a_value > 20),
          fetched_at:                 be_within(5.seconds).of(Time.current)
        )
      end
    end

    describe "which exists locally" do
      it_behaves_like "a package data update"
    end

    describe "which does not exist locally" do
      it "creates a new record" do
        expect { do_perform }.to change(Package, :count).by(1)
      end

      it_behaves_like "a package data update"
    end
  end

  describe "for a non-existent package", vcr: { cassette_name: :packagist_unknown_package } do
    let(:package_name) { "laravel-toolbox/there-is-no-such-package" }

    describe "which exists locally" do
      it "deletes the local record" do
        Package.create! name: package_name, downloads: 500, current_version: "123"
        expect { do_perform }.to change(Package, :count).by(-1)
      end
    end

    describe "which does not exist locally" do
      it "does not create a record" do
        expect { do_perform }.not_to(change(Package, :count))
      end
    end
  end
end
