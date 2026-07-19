# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::HouseDate do
  include ActiveSupport::Testing::TimeHelpers

  describe ".date" do
    it "renders '%-d %b' (no year, no leading zero) for a current-year date" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Date.new(2026, 6, 4))).to eq("4 Jun")
      end
    end

    it "renders '%-d %b' for a two-digit day too (no leading zero either way)" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Date.new(2026, 2, 23))).to eq("23 Feb")
      end
    end

    it "carries the short year for a PAST year" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Date.new(2025, 6, 5))).to eq("5 Jun '25")
      end
    end

    it "carries the short year for a FUTURE year" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Date.new(2027, 7, 26))).to eq("26 Jul '27")
      end
    end

    it "never collapses on today — a date-only value that IS today still renders the day" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Date.new(2026, 7, 19))).to eq("19 Jul")
      end
    end

    it "accepts a date-like (Time/TimeWithZone) argument via #to_date" do
      travel_to(Time.zone.local(2026, 7, 19)) do
        expect(described_class.date(Time.zone.local(2026, 6, 4, 23, 59))).to eq("4 Jun")
      end
    end
  end

  describe ".stamp" do
    it "collapses to bare '%H:%M' when the local date is today (date drops entirely)" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        expect(described_class.stamp(Time.zone.local(2026, 7, 19, 14, 30))).to eq("14:30")
      end
    end

    it "renders '%-d %b %H:%M' for a same-year, non-today time" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        expect(described_class.stamp(Time.zone.local(2026, 6, 2, 16, 30))).to eq("2 Jun 16:30")
      end
    end

    it "renders '%-d %b 'YY %H:%M' for a PAST year" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        expect(described_class.stamp(Time.zone.local(2025, 6, 2, 16, 30))).to eq("2 Jun '25 16:30")
      end
    end

    it "renders '%-d %b 'YY %H:%M' for a FUTURE year" do
      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        expect(described_class.stamp(Time.zone.local(2027, 1, 5, 8, 0))).to eq("5 Jan '27 08:00")
      end
    end

    it "returns the em-dash fallback for nil" do
      expect(described_class.stamp(nil)).to eq("—")
    end

    it "returns a custom fallback when given" do
      expect(described_class.stamp(nil, fallback: "never synced")).to eq("never synced")
    end

    it "converts a UTC time into the app's local zone before comparing to today" do
      original = Time.zone
      Time.zone = "Europe/Madrid" # UTC+2 in July (DST)

      travel_to(Time.zone.local(2026, 7, 19, 9, 0)) do
        # 22:00 UTC on the 18th is already 00:00 on the 19th in Madrid — the
        # SAME local day as "today", even though the UTC calendar day differs.
        utc = Time.utc(2026, 7, 18, 22, 0)
        expect(described_class.stamp(utc)).to eq("00:00")
      end
    ensure
      Time.zone = original
    end

    it "zero-pads hour and minute but NOT the day (no leading zero on the day, by design)" do
      travel_to(Time.zone.local(2026, 3, 10, 20, 0)) do
        expect(described_class.stamp(Time.zone.local(2026, 3, 4, 5, 6))).to eq("4 Mar 05:06")
      end
    end
  end
end
