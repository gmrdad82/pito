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

  # ── Delta form (OWNER DIRECTIVE Q17, 3.8.0) — see the module comment ─────
  describe ".delta?" do
    it "is true only for an explicitly signed token" do
      expect(described_class.delta?("+2")).to be(true)
      expect(described_class.delta?("-1.5")).to be(true)
      expect(described_class.delta?(" +2 ")).to be(true)
    end

    it "is false for a bare number (absolute set), non-numeric text, and nil" do
      expect(described_class.delta?("2")).to be(false)
      expect(described_class.delta?("abc")).to be(false)
      expect(described_class.delta?(nil)).to be(false)
    end
  end

  describe ".parse_delta" do
    it "parses a signed amount to an exact signed half-step Rational" do
      expect(described_class.parse_delta("+2")).to eq(2r)
      expect(described_class.parse_delta("-1.5")).to eq(-3r / 2)
    end

    it "ceils the MAGNITUDE to the next 0.5 step, keeping the sign" do
      expect(described_class.parse_delta("+2.1")).to eq(5r / 2)
      expect(described_class.parse_delta("-2.1")).to eq(-5r / 2)
    end

    it "returns nil for a bare (unsigned) number — that is the absolute form" do
      expect(described_class.parse_delta("2")).to be_nil
    end

    it "returns nil for a vague signed token (no clean magnitude)" do
      expect(described_class.parse_delta("+x")).to be_nil
      expect(described_class.parse_delta("-y")).to be_nil
      expect(described_class.parse_delta("+")).to be_nil
      expect(described_class.parse_delta("+-2")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.parse_delta("")).to be_nil
      expect(described_class.parse_delta(nil)).to be_nil
    end
  end
end
