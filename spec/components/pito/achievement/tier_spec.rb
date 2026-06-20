# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievement::Tier do
  # ── SERIES ────────────────────────────────────────────────────

  describe "SERIES" do
    it "is frozen" do
      expect(described_class::SERIES).to be_frozen
    end

    it "contains exactly 22 entries" do
      expect(described_class::SERIES.length).to eq(22)
    end

    it "starts at 1 and ends at 10_000_000" do
      expect(described_class::SERIES.first).to eq(1)
      expect(described_class::SERIES.last).to eq(10_000_000)
    end

    it "matches the canonical 22-step milestone sequence" do
      expect(described_class::SERIES).to eq([
        1, 2, 5,
        10, 20, 50,
        100, 200, 500,
        1_000, 2_000, 5_000,
        10_000, 20_000, 50_000,
        100_000, 200_000, 500_000,
        1_000_000, 2_000_000, 5_000_000,
        10_000_000
      ])
    end
  end

  # ── .token_for — all 8 tiers ─────────────────────────────────

  describe ".token_for" do
    {
               1 => "muted",    2 => "muted",    5 => "muted",
              10 => "green",   20 => "green",   50 => "green",
             100 => "cyan",   200 => "cyan",   500 => "cyan",
           1_000 => "blue",  2_000 => "blue",  5_000 => "blue",
          10_000 => "purple", 20_000 => "purple", 50_000 => "purple",
         100_000 => "orange", 200_000 => "orange", 500_000 => "orange",
       1_000_000 => "yellow", 2_000_000 => "yellow", 5_000_000 => "yellow",
      10_000_000 => "pito"
    }.each do |threshold, expected_token|
      it "maps #{threshold} → '#{expected_token}'" do
        expect(described_class.token_for(threshold)).to eq(expected_token)
      end
    end

    it "raises KeyError for an unrecognised threshold" do
      expect { described_class.token_for(999) }.to raise_error(KeyError)
    end
  end
end
