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

    it "parses `at 3:10am` as today 03:10" do
      expect(parse("5 at 3:10am").time).to eq(Time.zone.local(2026, 6, 16, 3, 10))
    end

    it "parses `at 15:30` (24-hour) as today 15:30" do
      expect(parse("5 at 15:30").time).to eq(Time.zone.local(2026, 6, 16, 15, 30))
    end

    it "parses `tomorrow at 3:10am` as tomorrow 03:10" do
      expect(parse("5 tomorrow at 3:10am").time).to eq(Time.zone.local(2026, 6, 17, 3, 10))
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

  describe "this-calendar-week bare weekday (Monday-first, week of 2026-06-15)" do
    it "parses `monday` as 2026-06-15 09:00 (already past — parser still returns it)" do
      expect(parse("5 monday").time).to eq(Time.zone.local(2026, 6, 15, 9, 0))
    end

    it "parses `tuesday` as 2026-06-16 09:00" do
      expect(parse("5 tuesday").time).to eq(Time.zone.local(2026, 6, 16, 9, 0))
    end

    it "parses `saturday at noon` as 2026-06-20 12:00" do
      expect(parse("5 saturday at noon").time).to eq(Time.zone.local(2026, 6, 20, 12, 0))
    end

    it "parses `sunday` as 2026-06-21 09:00" do
      expect(parse("5 sunday").time).to eq(Time.zone.local(2026, 6, 21, 9, 0))
    end

    it "parses `fri` (abbreviated) as 2026-06-19 09:00" do
      expect(parse("5 fri").time).to eq(Time.zone.local(2026, 6, 19, 9, 0))
    end

    it "parses `saturday night` as 2026-06-20 21:00" do
      expect(parse("5 saturday night").time).to eq(Time.zone.local(2026, 6, 20, 21, 0))
    end
  end

  describe "next-calendar-week forms" do
    it "parses `next week` as Monday 2026-06-22 09:00" do
      expect(parse("5 next week").time).to eq(Time.zone.local(2026, 6, 22, 9, 0))
    end

    it "parses `next week at 10am` as 2026-06-22 10:00" do
      expect(parse("5 next week at 10am").time).to eq(Time.zone.local(2026, 6, 22, 10, 0))
    end

    it "parses `next monday` as 2026-06-22 09:00" do
      expect(parse("5 next monday").time).to eq(Time.zone.local(2026, 6, 22, 9, 0))
    end

    it "parses `next thursday` as 2026-06-25 09:00" do
      expect(parse("5 next thursday").time).to eq(Time.zone.local(2026, 6, 25, 9, 0))
    end

    it "parses `next monday at 14:00` as 2026-06-22 14:00" do
      expect(parse("5 next monday at 14:00").time).to eq(Time.zone.local(2026, 6, 22, 14, 0))
    end

    it "parses `next friday at noon` as 2026-06-26 12:00" do
      expect(parse("5 next friday at noon").time).to eq(Time.zone.local(2026, 6, 26, 12, 0))
    end
  end

  describe "relative `N days/weeks from now` forms (date-anchored, default 9am)" do
    it "parses `4 days from now` as 2026-06-20 09:00" do
      expect(parse("5 4 days from now").time).to eq(Time.zone.local(2026, 6, 20, 9, 0))
    end

    it "parses `1 week from now at 13:00` as 2026-06-23 13:00" do
      expect(parse("5 1 week from now at 13:00").time).to eq(Time.zone.local(2026, 6, 23, 13, 0))
    end

    it "parses `2 weeks from now at noon` as 2026-06-30 12:00" do
      expect(parse("5 2 weeks from now at noon").time).to eq(Time.zone.local(2026, 6, 30, 12, 0))
    end

    it "parses `3 weeks from now` as 2026-07-07 09:00" do
      expect(parse("5 3 weeks from now").time).to eq(Time.zone.local(2026, 7, 7, 9, 0))
    end
  end

  describe "next month forms (1st of next month, default 9am)" do
    it "parses `next month` as 2026-07-01 09:00" do
      expect(parse("5 next month").time).to eq(Time.zone.local(2026, 7, 1, 9, 0))
    end

    it "parses `next month at noon` as 2026-07-01 12:00" do
      expect(parse("5 next month at noon").time).to eq(Time.zone.local(2026, 7, 1, 12, 0))
    end

    it "parses `next month at 6am` as 2026-07-01 06:00" do
      expect(parse("5 next month at 6am").time).to eq(Time.zone.local(2026, 7, 1, 6, 0))
    end
  end

  describe "tomorrow extensions" do
    it "parses `tomorrow night` as 2026-06-17 21:00" do
      expect(parse("5 tomorrow night").time).to eq(Time.zone.local(2026, 6, 17, 21, 0))
    end
  end

  describe "today forms (today = 2026-06-16; bare → 09:00, already past — parser still returns it)" do
    it "parses bare `today` as 2026-06-16 09:00" do
      expect(parse("5 today").time).to eq(Time.zone.local(2026, 6, 16, 9, 0))
    end

    it "parses `today at 14:30` (24-hour) as 2026-06-16 14:30" do
      expect(parse("5 today at 14:30").time).to eq(Time.zone.local(2026, 6, 16, 14, 30))
    end

    it "parses `today at 3am` as 2026-06-16 03:00" do
      expect(parse("5 today at 3am").time).to eq(Time.zone.local(2026, 6, 16, 3, 0))
    end

    it "parses `today at 5pm` as 2026-06-16 17:00" do
      expect(parse("5 today at 5pm").time).to eq(Time.zone.local(2026, 6, 16, 17, 0))
    end

    it "parses `today at noon` as 2026-06-16 12:00" do
      expect(parse("5 today at noon").time).to eq(Time.zone.local(2026, 6, 16, 12, 0))
    end

    it "keeps a multi-token `# id` ref before `today`" do
      result = parse("# 22 today at 14:30")
      expect(result.ref_tokens.map(&:value).join(" ").strip).to eq("# 22")
      expect(result.time).to eq(Time.zone.local(2026, 6, 16, 14, 30))
    end
  end

  describe "owner QoL grammar lock" do
    # Pins the owner's everyday phrasing verbatim so the mass/batch path
    # (lib/pito/chat/handlers/schedule.rb parse_mass_segment), which shares
    # THIS SAME parser, can never silently regress on these forms.
    it "parses `2 days from now` as 2026-06-18 09:00" do
      expect(parse("5 2 days from now").time).to eq(Time.zone.local(2026, 6, 18, 9, 0))
    end

    # `next monday` is already asserted verbatim above (this same input/result)
    # in "next-calendar-week forms" — skipped here to avoid duplicating it.

    it "parses `next monday 3pm` as 2026-06-22 15:00" do
      expect(parse("5 next monday 3pm").time).to eq(Time.zone.local(2026, 6, 22, 15, 0))
    end

    it "parses `at 3pm` as today 15:00" do
      expect(parse("5 at 3pm").time).to eq(Time.zone.local(2026, 6, 16, 15, 0))
    end

    it "parses `tomorrow 11am` as tomorrow 11:00" do
      expect(parse("5 tomorrow 11am").time).to eq(Time.zone.local(2026, 6, 17, 11, 0))
    end

    # `in 2 hours` is already asserted verbatim above (this same input/result)
    # in "relative `in …` durations" — skipped here to avoid duplicating it.

    it "parses `20-07-2026 20:00`" do
      expect(parse("5 20-07-2026 20:00").time).to eq(Time.zone.local(2026, 7, 20, 20, 0))
    end
  end

  describe "unparseable phrases" do
    it "returns nil for free text" do
      expect(parse("5 next-tuesday")).to be_nil
    end

    it "returns nil when there is no <when> at all" do
      expect(parse("5")).to be_nil
    end

    it "returns nil for `next blursday` (not a weekday)" do
      expect(parse("5 next blursday")).to be_nil
    end

    it "returns nil for `saturday at 25pm` (invalid time-of-day)" do
      expect(parse("5 saturday at 25pm")).to be_nil
    end
  end
end
