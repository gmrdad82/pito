require "rails_helper"

# Phase 26 — 01a. Timezone foundation render-layer helpers.
#
# `l_user_tz(time, format:)` converts a stored-UTC timestamp into the
# user's local-zone formatted string. `Time.zone` is set per-request
# by `ApplicationController#set_user_time_zone`; in the helper spec
# we set it directly via `Time.use_zone` so each example exercises a
# fully-isolated zone.
RSpec.describe TimeZoneHelper, type: :helper do
  describe "#l_user_tz" do
    it "returns the literal em-dash for nil input" do
      expect(helper.l_user_tz(nil)).to eq("—")
    end

    it "returns em-dash for nil with an explicit format too" do
      expect(helper.l_user_tz(nil, format: :short)).to eq("—")
    end

    it "renders a UTC instant in the user's zone (Europe/Bucharest, EEST in summer)" do
      Time.use_zone("Europe/Bucharest") do
        # 2026-06-15 12:00 UTC → 15:00 EEST (Bucharest is UTC+3 in DST).
        utc = Time.utc(2026, 6, 15, 12, 0, 0)
        out = helper.l_user_tz(utc, format: :long)
        expect(out).to include("15:00")
        expect(out).to include("Jun 15, 2026")
      end
    end

    it "renders a UTC instant in the user's zone (Europe/Bucharest, EET in winter)" do
      Time.use_zone("Europe/Bucharest") do
        # 2026-01-15 12:00 UTC → 14:00 EET (Bucharest is UTC+2 outside DST).
        utc = Time.utc(2026, 1, 15, 12, 0, 0)
        out = helper.l_user_tz(utc, format: :long)
        expect(out).to include("14:00")
      end
    end

    it "honors the Pacific/Kiritimati +14 edge zone" do
      Time.use_zone("Pacific/Kiritimati") do
        # 2026-06-01 00:00 UTC → 14:00 same day on Kiritimati (UTC+14).
        utc = Time.utc(2026, 6, 1, 0, 0, 0)
        out = helper.l_user_tz(utc, format: :short)
        expect(out).to include("14:00")
      end
    end

    it "honors the Pacific/Pago_Pago -11 edge zone" do
      Time.use_zone("Pacific/Pago_Pago") do
        # 2026-06-01 12:00 UTC → 01:00 same day on Pago Pago (UTC-11).
        utc = Time.utc(2026, 6, 1, 12, 0, 0)
        out = helper.l_user_tz(utc, format: :short)
        expect(out).to include("01:00")
      end
    end

    it "honors the Asia/Kolkata half-hour offset (UTC+5:30)" do
      Time.use_zone("Asia/Kolkata") do
        # 2026-06-01 06:30 UTC → 12:00 IST.
        utc = Time.utc(2026, 6, 1, 6, 30, 0)
        out = helper.l_user_tz(utc, format: :short)
        expect(out).to include("12:00")
      end
    end

    it "accepts a Time instance" do
      Time.use_zone("Etc/UTC") do
        t = Time.utc(2026, 5, 10, 9, 0, 0)
        expect(helper.l_user_tz(t, format: :short)).to include("09:00")
      end
    end

    it "accepts a DateTime instance" do
      Time.use_zone("Etc/UTC") do
        dt = DateTime.new(2026, 5, 10, 9, 0, 0)
        expect(helper.l_user_tz(dt, format: :short)).to include("09:00")
      end
    end

    it "accepts an ActiveSupport::TimeWithZone instance" do
      Time.use_zone("America/Los_Angeles") do
        twz = Time.utc(2026, 5, 10, 16, 0, 0).in_time_zone("America/Los_Angeles")
        expect(helper.l_user_tz(twz, format: :short)).to include("09:00")
      end
    end

    it "supports :date format (no clock component)" do
      Time.use_zone("Etc/UTC") do
        out = helper.l_user_tz(Time.utc(2026, 5, 10, 9, 0, 0), format: :date)
        expect(out).to eq("May 10, 2026")
      end
    end

    it "supports :iso format (full ISO 8601)" do
      Time.use_zone("Europe/Bucharest") do
        out = helper.l_user_tz(Time.utc(2026, 6, 15, 12, 0, 0), format: :iso)
        expect(out).to match(/\A2026-06-15T15:00:00\+03:00\z/)
      end
    end

    it "treats unknown format symbols as :long (graceful fallback)" do
      Time.use_zone("Etc/UTC") do
        out = helper.l_user_tz(Time.utc(2026, 5, 10, 9, 0, 0), format: :totally_made_up)
        expect(out).to include("09:00")
      end
    end

    it "crosses a DST spring-forward correctly (America/New_York 2026-03-08)" do
      Time.use_zone("America/New_York") do
        # 2026-03-08 06:30 UTC sits one minute before the DST jump.
        # Before jump: 01:30 EST. After jump: 03:30 EDT. We test the
        # post-jump side at 07:30 UTC → 03:30 EDT.
        pre  = Time.utc(2026, 3, 8, 6, 30, 0)
        post = Time.utc(2026, 3, 8, 7, 30, 0)
        expect(helper.l_user_tz(pre,  format: :short)).to include("01:30")
        expect(helper.l_user_tz(post, format: :short)).to include("03:30")
      end
    end

    it "crosses a DST fall-back correctly (America/New_York 2026-11-01)" do
      Time.use_zone("America/New_York") do
        # 2026-11-01 05:00 UTC → 01:00 EDT. 2026-11-01 06:00 UTC → 01:00 EST.
        # Both render as 01:00 but the zone abbreviation flips.
        pre  = Time.utc(2026, 11, 1, 5, 0, 0)
        post = Time.utc(2026, 11, 1, 6, 0, 0)
        out_pre  = helper.l_user_tz(pre,  format: :short)
        out_post = helper.l_user_tz(post, format: :short)
        expect(out_pre).to include("01:00")
        expect(out_post).to include("01:00")
        # The zone abbreviations differ across the fall-back boundary.
        expect(out_pre).not_to eq(out_post)
      end
    end
  end

  describe "#current_time_in_user_tz" do
    it "renders Time.current through the configured zone in :short format" do
      Time.use_zone("Europe/Bucharest") do
        out = helper.current_time_in_user_tz
        # Format `HH:MM ZONE` — assert the shape rather than the
        # exact clock (which changes every second).
        expect(out).to match(/\A\d{2}:\d{2} [A-Z+\-0-9]+\z/)
      end
    end

    it "accepts a format override (forwards to l_user_tz)" do
      Time.use_zone("Etc/UTC") do
        out = helper.current_time_in_user_tz(format: :iso)
        # Etc/UTC renders as `Z` (Ruby's `iso8601` short form for UTC).
        expect(out).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|\+00:00)\z/)
      end
    end
  end
end
