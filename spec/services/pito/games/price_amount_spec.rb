# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Games::PriceAmount — the single canonical amount parser,
# now consumed solely by Chat::Handlers::Update's price field (the standalone
# `price` verb, its follow-up reply, and the `:price_amount` resolver retired
# with the tool consolidation; born plan-0.9.5 T8.15).
RSpec.describe Pito::Games::PriceAmount do
  describe ".parse" do
    it "parses a euro amount to a 2dp BigDecimal" do
      expect(described_class.parse("9.99")).to eq(BigDecimal("9.99"))
    end

    it "rounds to 2 decimals" do
      expect(described_class.parse("9.999")).to eq(BigDecimal("10.0"))
    end

    it "accepts an explicit 0 (free)" do
      expect(described_class.parse("0")).to eq(BigDecimal("0"))
    end

    it "returns nil for a negative value" do
      expect(described_class.parse("-1")).to be_nil
    end

    it "returns nil for blank / non-numeric input" do
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("free")).to be_nil
    end
  end
end
