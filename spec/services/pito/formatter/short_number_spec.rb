# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::ShortNumber do
  describe ".call" do
    # Each row corresponds to the docblock truth table on the module.
    # Mirrors the JS counterpart in
    # `app/javascript/controllers/tui_sidekiq_stats_controller.js#shortFormat`.
    {
      0              => "0",
      1              => "1",
      32             => "32",
      111            => "111",
      999            => "999",
      1_000          => "1k",
      1_001          => "1k",
      22_345         => "22k",
      45_000         => "45k",
      899_000        => "899k",
      999_999        => "999k",
      1_000_000      => "1M",
      1_500_000      => "1M",
      999_999_999    => "999M",
      1_000_000_000  => "1B"
    }.each do |input, expected|
      it "formats #{input} as #{expected.inspect}" do
        expect(described_class.call(input)).to eq(expected)
      end
    end

    it "returns an empty string for nil" do
      expect(described_class.call(nil)).to eq("")
    end

    it "treats negative values as their absolute value" do
      expect(described_class.call(-5)).to eq("5")
      expect(described_class.call(-22_345)).to eq("22k")
    end
  end
end
