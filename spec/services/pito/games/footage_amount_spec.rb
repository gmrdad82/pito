# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Games::FootageAmount — the single canonical parser the
# `footage` chat verb, its GameDetail follow-up reply, and the `:footage_hours`
# dispatch resolver all share (plan-0.9.5 T8.15).
RSpec.describe Pito::Games::FootageAmount do
  describe ".parse" do
    it "parses a bare hours value to an exact half-step Rational" do
      expect(described_class.parse("12.5")).to eq(25r / 2)
    end

    it "tolerates a leading `update` token (parity with the chat verb form)" do
      expect(described_class.parse("update 12.5")).to eq(25r / 2)
    end

    it "ceils UP to the next clean 0.5 step" do
      expect(described_class.parse("2.1")).to eq(5r / 2)   # 2.5h
      expect(described_class.parse("5")).to eq(5r)         # already a step
    end

    it "keeps an exact Rational (no float drift)" do
      expect(described_class.parse("0.5")).to be_a(Rational).and eq(1r / 2)
    end

    it "returns nil for a negative value" do
      expect(described_class.parse("-1")).to be_nil
    end

    it "returns nil for non-numeric input" do
      expect(described_class.parse("abc")).to be_nil
      expect(described_class.parse("")).to be_nil
      expect(described_class.parse(nil)).to be_nil
    end
  end
end
