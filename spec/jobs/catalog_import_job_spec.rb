# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogImportJob do
  fixtures :all

  let(:job) { described_class.new }

  describe "#perform" do
    it "imports the catalog checked into the repo" do
      expected = JSON.parse Rails.root.join(described_class::LOCAL_CATALOG_PATH).read

      expect(CatalogImport).to receive(:perform).with(expected)
      job.perform
    end

    it "queues a CategoryRankingJob" do
      allow(CatalogImport).to receive(:perform)
      expect(CategoryRankingJob).to receive(:perform_async)
      job.perform
    end

    describe "with a remotely hosted catalog" do
      let(:catalog_body) { Rails.root.join("lib", "base-catalog.json").read }
      let(:catalog_url) { "https://example.com/catalog.json" }

      def stub_response(status: 200)
        response = HTTP::Response.new(
          status:,
          body:    catalog_body,
          version: "1.1"
        )
        allow(job.http_client).to receive(:get).with(catalog_url).and_return(response)
      end

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("CATALOG_URL", nil).and_return(catalog_url)
      end

      it "fetches the catalog" do
        expect(job.http_client).to receive(:get).with(catalog_url)

        stub_response
        job.perform
      end

      it "raises an error when fetching fails" do
        stub_response status: 502
        expect { job.perform }.to raise_error(/response status was 502/)
      end

      it "passes the parsed body to CatalogImport.perform" do
        stub_response
        expect(CatalogImport).to receive(:perform).with(JSON.parse(catalog_body))
        job.perform
      end
    end
  end
end
