# frozen_string_literal: true

require "rails_helper"

RSpec.describe Laravel do
  describe ".versions_for" do
    it "reads the constraint off the illuminate components" do
      requirements = {
        "php"                  => "^8.3",
        "illuminate/contracts" => "^12.0|^13.0",
        "illuminate/database"  => "^12.0|^13.0",
      }

      expect(described_class.versions_for(requirements)).to eq [12, 13]
    end

    it "reads the constraint off laravel/framework" do
      expect(described_class.versions_for({ "laravel/framework" => "^11.0|^12.0" })).to eq [11, 12]
    end

    #
    # Composer AND-s separate requirements, so the package can only be used with
    # the versions every one of its laravel dependencies allows.
    #
    it "intersects the constraints when they disagree" do
      requirements = {
        "illuminate/support" => "^11.0|^12.0",
        "illuminate/console" => "^12.0",
      }

      expect(described_class.versions_for(requirements)).to eq [12]
    end

    it "enumerates open ended constraints up to the latest known version" do
      expect(described_class.versions_for({ "laravel/framework" => ">=12.0" }))
        .to eq (12..described_class::LATEST_VERSION).to_a
    end

    it "returns nothing for packages that do not depend on laravel at all" do
      expect(described_class.versions_for({ "php" => "^8.3", "brick/money" => "^0.9" })).to eq []
    end

    it "returns nothing for missing requirements" do
      expect(described_class.versions_for(nil)).to eq []
    end
  end

  describe ".requirement_for" do
    it "prefers laravel/framework over the illuminate components" do
      requirements = {
        "illuminate/contracts" => "^12.0",
        "laravel/framework"    => "^12.0|^13.0",
      }

      expect(described_class.requirement_for(requirements)).to eq "^12.0|^13.0"
    end

    it "falls back to an illuminate component" do
      expect(described_class.requirement_for({ "illuminate/database" => "^12.0" })).to eq "^12.0"
    end

    it "is nil without a laravel dependency" do
      expect(described_class.requirement_for({ "php" => "^8.3" })).to be_nil
    end
  end
end
