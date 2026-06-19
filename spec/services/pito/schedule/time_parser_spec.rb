# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Schedule::TimeParser do
  include ActiveSupport::Testing::TimeHelpers

  # A fixed, DST-free zone + instant so every assertion is deterministic.
  # NOW is Tuesday 2026-06-16 10:00 local; TODAY = the 16th, TOMORROW = the 17th.
  NOW = Time.find_zone("UTC").local(2026, 6, 16, 10, 0)

  around do |example|
    Time.use_zone("UTC") { travel_to(NOW) { example.run } }
  end

  # Lex a full "<ref> <when>" string and parse it, exactly as the handler does
  # (the handler passes message.body_tokens through). The lexer's :eof sentinel
  # is rejected inside the parser.
  def parse(input)
    described_class.call(Pito::Lex::Lexer.call(input))
  end

  describe "relative `in …` durations (computed from Time.current)" do
    it "parses `in 30m`" do
      expect(parse("5 in 30m").time).to eq(Time.zone.local(2026, 6, 16, 10, 30))
    end

    it "parses `in 30 minutes`" do
      expect(parse("5 in 30 minutes").time).to eq(Time.zone.local(2026, 6, 16, 10, 30))
    end

    it "parses `in 5 min`" do
      expect(parse("5 in 5 min").time).to eq(Time.zone.local(2026, 6, 16, 10, 5))
    end

    it "parses `in 1h`" do
      expect(parse("5 in 1h").time).to eq(Time.zone.local(2026, 6, 16, 11, 0))
    end

    it "parses `in 1 hour from now`" do
      expect(parse("5 in 1 hour from now").time).to eq(Time.zone.local(2026, 6, 16, 11, 0))
    end

    it "parses `in 2 hours`" do
      expect(parse("5 in 2 hours").time).to eq(Time.zone.local(2026, 6, 16, 12, 0))
    end

    it "parses `in 3 days` as that calendar date at 09:00 local" do
      expect(parse("5 in 3 days").time).to eq(Time.zone.local(2026, 6, 19, 9, 0))
    end
  end

  describe "named day/time forms (built in Time.zone)" do
    it "parses `tomorrow` as tomorrow 09:00" do
      expect(parse("5 tomorrow").time).to eq(Time.zone.local(2026, 6, 17, 9, 0))
    end

    it "parses `tomorrow at noon` as tomorrow 12:00" do
      expect(parse("5 tomorrow at noon").time).to eq(Time.zone.local(2026, 6, 17, 12, 0))
    end

    it "parses `at 2pm` as today 14:00" do
      expect(parse("5 at 2pm").time).to eq(Time.zone.local(2026, 6, 16, 14, 0))
    end

    it "parses `at 11pm` as today 23:00" do
      expect(parse("5 at 11pm").time).to eq(Time.zone.local(2026, 6, 16, 23, 0))
    end

    it "parses `at 23` (24-hour) as today 23:00" do
      expect(parse("5 at 23").time).to eq(Time.zone.local(2026, 6, 16, 23, 0))
    end

    it "rejects a 24-hour `at` value out of range (`at 25`)" do
      expect(parse("5 at 25")).to be_nil
    end
  end

  describe "absolute date forms (`.` and `-` separators, optional `for`)" do
    it "parses `for DD.MM.YYYY HH:MM`" do
      expect(parse("5 for 20.06.2026 14:30").time).to eq(Time.zone.local(2026, 6, 20, 14, 30))
    end

    it "parses `for DD-MM-YYYY HH:MM`" do
      expect(parse("5 for 20-06-2026 14:30").time).to eq(Time.zone.local(2026, 6, 20, 14, 30))
    end

    it "parses bare `DD-MM-YYYY HH:MM`" do
      expect(parse("5 20-06-2026 14:30").time).to eq(Time.zone.local(2026, 6, 20, 14, 30))
    end

    it "parses bare `DD-MM-YYYY` (date-only) at 09:00 local" do
      expect(parse("5 20-06-2026").time).to eq(Time.zone.local(2026, 6, 20, 9, 0))
    end

    it "parses bare `DD.MM.YYYY` (date-only) at 09:00 local" do
      expect(parse("5 20.06.2026").time).to eq(Time.zone.local(2026, 6, 20, 9, 0))
    end

    it "returns nil for a calendrically invalid date (month 99)" do
      expect(parse("5 01-99-2025")).to be_nil
    end
  end

  describe "ref extraction" do
    it "keeps a bare numeric id as the ref" do
      result = parse("5 in 2 hours")
      expect(result.ref_tokens.map(&:value).join).to eq("5")
    end

    it "keeps a multi-token `# id` ref" do
      result = parse("# 5 tomorrow")
      expect(result.ref_tokens.map(&:value).join(" ").strip).to eq("# 5")
    end
  end

  describe "unparseable phrases" do
    it "returns nil for free text" do
      expect(parse("5 next-tuesday")).to be_nil
    end

    it "returns nil when there is no <when> at all" do
      expect(parse("5")).to be_nil
    end
  end
end
