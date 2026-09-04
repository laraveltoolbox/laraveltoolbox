# frozen_string_literal: true

require "rails_helper"

RSpec.describe Composer::Constraint do
  describe "#major_versions" do
    subject(:major_versions) { described_class.new(constraint, ceiling: 13).major_versions }

    {
      # The shapes that actually show up in laravel packages' composer.json
      "^12.0|^13.0"                => [12, 13],
      "^11.0 || ^12.0 || ^13.0"    => [11, 12, 13],
      "^11.0||^12.0||^13.0"        => [11, 12, 13],
      "^11.0 | ^12.0 | ^13.0"      => [11, 12, 13],
      "12.*|13.*"                  => [12, 13],
      "6.*|7.*|8.*"                => [6, 7, 8],
      "^13.0"                      => [13],
      "^13"                        => [13],
      "^10|^11.0|^12.0"            => [10, 11, 12],
      "^11.44.2 || ^12.4.1 || ^13" => [11, 12, 13],
      "~10.0"                      => [10],
      "~10.0.0"                    => [10],
      "5.1.* || 5.2.* || 5.3.*"    => [5],
      "10.0"                       => [10],

      # Open ended constraints get enumerated up to the ceiling
      ">=12.0"                     => [12, 13],
      ">= 10.0"                    => [10, 11, 12, 13],
      "*"                          => (0..13).to_a,

      # Upper bounds
      "<13.0"                      => (0..12).to_a,
      "<=12.0"                     => (0..12).to_a,

      # Space separated comparators are AND-ed, so only the overlap survives
      ">=10.0 <12.0"               => [10, 11],

      ""                           => [],
      nil                          => [],
    }.each do |constraint, expected|
      context "with #{constraint.inspect}" do
        let(:constraint) { constraint }

        it { is_expected.to eq expected }
      end
    end

    it "returns nothing for a constraint that cannot be satisfied" do
      expect(described_class.new(">=12.0 <11.0", ceiling: 13).major_versions).to be_empty
    end

    #
    # Exclusions are rare enough in the wild that modelling them is not worth
    # the complexity - we deliberately widen rather than narrow, so a package is
    # never hidden from a version it might actually support.
    #
    it "ignores exclusions" do
      expect(described_class.new("!=12.0", ceiling: 13).major_versions).to eq (0..13).to_a
    end
  end

  describe "#minimum_version" do
    subject(:minimum_version) { described_class.new(constraint).minimum_version }

    {
      "^8.3"                       => "8.3",
      "^8.2.0"                     => "8.2",
      "^8.2|^8.3|^8.4"             => "8.2",
      "^7.1 || ^8.0"               => "7.1",
      ">=8.2"                      => "8.2",
      ">= 7.1.0"                   => "7.1",
      ">=5.5.9"                    => "5.5",
      ">=8.2 <8.6"                 => "8.2",
      "~7.4.0 || ~8.0.0 || ~8.1.0" => "7.4",
      "8.5"                        => "8.5",
      "*"                          => nil,
      ""                           => nil,
      nil                          => nil,
    }.each do |constraint, expected|
      context "with #{constraint.inspect}" do
        let(:constraint) { constraint }

        it { is_expected.to eq expected }
      end
    end
  end
end
