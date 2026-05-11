require "rails_helper"

# Phase 26 — 01h. Scheduled-publish tz wiring.
#
# `ScheduledPublishHelper` is the single conversion site between the
# user-local picker (date + time strings) and the UTC instant stored
# on `videos.publish_at`. Covers:
#
#   - Round-trip identity (user-local → UTC → user-local).
#   - DST spring-forward gap rejected with the friendly error.
#   - DST fall-back resolved to the first occurrence + warning.
#   - Edge zones: UTC+14, UTC-11, UTC+5:30, UTC+8:45.
#   - Reminder window offsets across DST.
RSpec.describe ScheduledPublishHelper, type: :helper do
  describe "#parse_user_local_to_utc" do
    it "parses a user-local date+time in Europe/Bucharest (DST) to UTC" do
      result = helper.parse_user_local_to_utc("2026-06-01", "09:00",
                                              "Europe/Bucharest")
      # Bucharest is UTC+3 in DST → 09:00 local == 06:00 UTC.
      expect(result.utc).to eq(Time.utc(2026, 6, 1, 6, 0, 0))
      expect(result.warning).to be_nil
    end

    it "parses a user-local date+time in Europe/Bucharest (winter, no DST) to UTC" do
      result = helper.parse_user_local_to_utc("2026-01-15", "09:00",
                                              "Europe/Bucharest")
      # Bucharest is UTC+2 outside DST → 09:00 local == 07:00 UTC.
      expect(result.utc).to eq(Time.utc(2026, 1, 15, 7, 0, 0))
      expect(result.warning).to be_nil
    end

    it "round-trips losslessly under normal conditions" do
      Time.use_zone("Europe/Bucharest") do
        result = helper.parse_user_local_to_utc("2026-06-01", "09:00",
                                                "Europe/Bucharest")
        rendered = helper.render_publish_at_for_user(result.utc,
                                                     "Europe/Bucharest")
        expect(rendered).to eq("2026-06-01T09:00")
      end
    end

    it "accepts the combined ISO 8601 form (single string, no separator)" do
      result = helper.parse_user_local_to_utc("2026-06-01T09:00", nil,
                                              "Europe/Bucharest")
      expect(result.utc).to eq(Time.utc(2026, 6, 1, 6, 0, 0))
    end

    it "accepts the combined form with seconds" do
      result = helper.parse_user_local_to_utc("2026-06-01T09:00:00", nil,
                                              "Europe/Bucharest")
      expect(result.utc).to eq(Time.utc(2026, 6, 1, 6, 0, 0))
    end

    it "returns nil when date_str is blank" do
      expect(helper.parse_user_local_to_utc("", "09:00", "Etc/UTC")).to be_nil
      expect(helper.parse_user_local_to_utc(nil, nil, "Etc/UTC")).to be_nil
    end

    it "raises AmbiguousLocalTime on garbage input" do
      expect {
        helper.parse_user_local_to_utc("not a date", nil, "Etc/UTC")
      }.to raise_error(ScheduledPublishHelper::AmbiguousLocalTime)
    end

    it "raises AmbiguousLocalTime on an unknown time zone" do
      expect {
        helper.parse_user_local_to_utc("2026-06-01", "09:00", "Mars/Olympus_Mons")
      }.to raise_error(ScheduledPublishHelper::AmbiguousLocalTime,
                       /unknown time zone/)
    end

    it "defaults the user_tz to Etc/UTC when nil" do
      result = helper.parse_user_local_to_utc("2026-06-01", "09:00", nil)
      expect(result.utc).to eq(Time.utc(2026, 6, 1, 9, 0, 0))
    end

    describe "DST spring-forward (America/Los_Angeles 2026-03-08)" do
      it "rejects 02:30 LA — the local hour 02:00–03:00 does not exist" do
        expect {
          helper.parse_user_local_to_utc("2026-03-08", "02:30",
                                         "America/Los_Angeles")
        }.to raise_error(ScheduledPublishHelper::AmbiguousLocalTime,
                         /does not exist due to DST spring-forward/)
      end

      it "accepts 03:30 LA — past the gap" do
        result = helper.parse_user_local_to_utc("2026-03-08", "03:30",
                                                "America/Los_Angeles")
        # LA is UTC-7 after the spring-forward → 03:30 PDT == 10:30 UTC.
        expect(result.utc).to eq(Time.utc(2026, 3, 8, 10, 30, 0))
      end

      it "accepts 01:30 LA — before the gap (still PST)" do
        result = helper.parse_user_local_to_utc("2026-03-08", "01:30",
                                                "America/Los_Angeles")
        # LA is UTC-8 before the spring-forward → 01:30 PST == 09:30 UTC.
        expect(result.utc).to eq(Time.utc(2026, 3, 8, 9, 30, 0))
      end
    end

    describe "DST fall-back (America/Los_Angeles 2026-11-01)" do
      it "resolves 01:30 LA to the FIRST occurrence (pre-fallback, PDT) and warns" do
        result = helper.parse_user_local_to_utc("2026-11-01", "01:30",
                                                "America/Los_Angeles")
        # Pre-fallback LA is UTC-7 → 01:30 PDT == 08:30 UTC.
        expect(result.utc).to eq(Time.utc(2026, 11, 1, 8, 30, 0))
        expect(result.warning).to eq(:dst_fallback_first_occurrence)
      end

      it "accepts 00:30 LA (well before fall-back) without warning" do
        result = helper.parse_user_local_to_utc("2026-11-01", "00:30",
                                                "America/Los_Angeles")
        # Still PDT → 00:30 PDT == 07:30 UTC.
        expect(result.utc).to eq(Time.utc(2026, 11, 1, 7, 30, 0))
        expect(result.warning).to be_nil
      end

      it "accepts 03:00 LA (well after fall-back) without warning" do
        result = helper.parse_user_local_to_utc("2026-11-01", "03:00",
                                                "America/Los_Angeles")
        # Post-fallback PST → 03:00 PST == 11:00 UTC.
        expect(result.utc).to eq(Time.utc(2026, 11, 1, 11, 0, 0))
        expect(result.warning).to be_nil
      end
    end

    describe "edge zones" do
      it "handles Pacific/Kiritimati (UTC+14)" do
        result = helper.parse_user_local_to_utc("2026-06-01", "14:00",
                                                "Pacific/Kiritimati")
        # 14:00 Kiritimati == 00:00 UTC same date.
        expect(result.utc).to eq(Time.utc(2026, 6, 1, 0, 0, 0))
      end

      it "handles Pacific/Pago_Pago (UTC-11)" do
        result = helper.parse_user_local_to_utc("2026-06-01", "01:00",
                                                "Pacific/Pago_Pago")
        # 01:00 Pago Pago == 12:00 UTC same date.
        expect(result.utc).to eq(Time.utc(2026, 6, 1, 12, 0, 0))
      end

      it "handles Asia/Kolkata (UTC+5:30)" do
        result = helper.parse_user_local_to_utc("2026-06-01", "12:00",
                                                "Asia/Kolkata")
        # 12:00 IST == 06:30 UTC.
        expect(result.utc).to eq(Time.utc(2026, 6, 1, 6, 30, 0))
      end

      it "handles Australia/Eucla (UTC+8:45)" do
        result = helper.parse_user_local_to_utc("2026-06-01", "12:00",
                                                "Australia/Eucla")
        # 12:00 Eucla == 03:15 UTC.
        expect(result.utc).to eq(Time.utc(2026, 6, 1, 3, 15, 0))
      end
    end

    describe "midnight boundaries" do
      it "handles 00:00 on the day boundary" do
        result = helper.parse_user_local_to_utc("2026-06-01", "00:00",
                                                "Europe/Bucharest")
        # 00:00 EEST == 21:00 UTC previous day.
        expect(result.utc).to eq(Time.utc(2026, 5, 31, 21, 0, 0))
      end

      it "handles 23:59 on the day boundary" do
        result = helper.parse_user_local_to_utc("2026-06-01", "23:59",
                                                "Pacific/Pago_Pago")
        # 23:59 Pago Pago == 10:59 UTC next day.
        expect(result.utc).to eq(Time.utc(2026, 6, 2, 10, 59, 0))
      end
    end
  end

  describe "#render_publish_at_for_user" do
    it "renders a UTC instant as a user-local picker string (DST)" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 0, 0),
        "Europe/Bucharest"
      )
      # Bucharest is UTC+3 in DST → 06:00 UTC == 09:00 local.
      expect(out).to eq("2026-06-01T09:00")
    end

    it "renders the same UTC instant differently across two zones (DST)" do
      utc = Time.utc(2026, 6, 1, 6, 0, 0)
      bucharest = helper.render_publish_at_for_user(utc, "Europe/Bucharest")
      la = helper.render_publish_at_for_user(utc, "America/Los_Angeles")
      # Bucharest UTC+3 → 09:00; LA UTC-7 → 23:00 previous day.
      expect(bucharest).to eq("2026-06-01T09:00")
      expect(la).to eq("2026-05-31T23:00")
    end

    it "returns nil for nil input" do
      expect(helper.render_publish_at_for_user(nil, "Europe/Bucharest")).to be_nil
    end

    it "falls back to Etc/UTC on an unknown zone" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 0, 0),
        "Mars/Olympus_Mons"
      )
      expect(out).to eq("2026-06-01T06:00")
    end

    it "defaults the user_tz to Etc/UTC when nil" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 0, 0),
        nil
      )
      expect(out).to eq("2026-06-01T06:00")
    end

    it "supports the :long format" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 0, 0),
        "Europe/Bucharest",
        format: :long
      )
      expect(out).to include("09:00")
      expect(out).to include("Jun 1, 2026")
    end

    it "supports the :iso format" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 0, 0),
        "Europe/Bucharest",
        format: :iso
      )
      expect(out).to eq("2026-06-01T09:00:00+03:00")
    end

    it "renders the Asia/Kolkata half-hour offset correctly" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 6, 30, 0),
        "Asia/Kolkata"
      )
      expect(out).to eq("2026-06-01T12:00")
    end

    it "renders the Australia/Eucla quarter-hour offset correctly" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 3, 15, 0),
        "Australia/Eucla"
      )
      expect(out).to eq("2026-06-01T12:00")
    end

    it "renders the Pacific/Kiritimati UTC+14 edge zone correctly" do
      out = helper.render_publish_at_for_user(
        Time.utc(2026, 6, 1, 0, 0, 0),
        "Pacific/Kiritimati"
      )
      # +14 → 14:00 same day.
      expect(out).to eq("2026-06-01T14:00")
    end
  end

  describe "#reminder_window" do
    it "computes a 1-hour-prior UTC instant" do
      out = helper.reminder_window(
        Time.utc(2026, 6, 1, 7, 0, 0),
        "Europe/Bucharest",
        offset: -1.hour
      )
      expect(out).to eq(Time.utc(2026, 6, 1, 6, 0, 0))
    end

    it "computes a 30-minute-prior UTC instant" do
      out = helper.reminder_window(
        Time.utc(2026, 6, 1, 7, 0, 0),
        "Europe/Bucharest",
        offset: -30.minutes
      )
      expect(out).to eq(Time.utc(2026, 6, 1, 6, 30, 0))
    end

    it "returns the same UTC instant across two zones (offset is timezone-invariant)" do
      publish_at = Time.utc(2026, 6, 1, 7, 0, 0)
      bucharest = helper.reminder_window(publish_at, "Europe/Bucharest",
                                          offset: -1.hour)
      la = helper.reminder_window(publish_at, "America/Los_Angeles",
                                  offset: -1.hour)
      expect(bucharest).to eq(la)
    end

    it "round-trips through DST spring-forward" do
      # A reminder 1 hour before a 03:30 LA publish (which is 10:30 UTC
      # after the spring-forward) lands at 09:30 UTC. Rendered back in
      # LA, that is 01:30 PST — i.e. before the spring-forward.
      publish_at = Time.utc(2026, 3, 8, 10, 30, 0)
      reminder = helper.reminder_window(publish_at, "America/Los_Angeles",
                                        offset: -1.hour)
      expect(reminder).to eq(Time.utc(2026, 3, 8, 9, 30, 0))
      rendered = helper.render_publish_at_for_user(reminder,
                                                   "America/Los_Angeles")
      expect(rendered).to eq("2026-03-08T01:30")
    end

    it "returns nil when publish_at_utc is nil" do
      expect(helper.reminder_window(nil, "Etc/UTC", offset: -1.hour)).to be_nil
    end

    it "returns nil when offset is nil" do
      expect(helper.reminder_window(
        Time.utc(2026, 6, 1, 7, 0, 0),
        "Etc/UTC",
        offset: nil
      )).to be_nil
    end

    it "computes 1-hour-prior in user-local clock for a 09:00 publish" do
      # 09:00 user-local in Europe/Bucharest (DST) is 06:00 UTC.
      # 1 hour earlier is 05:00 UTC == 08:00 Bucharest local.
      result = helper.parse_user_local_to_utc("2026-06-01", "09:00",
                                              "Europe/Bucharest")
      reminder = helper.reminder_window(result.utc, "Europe/Bucharest",
                                        offset: -1.hour)
      rendered = helper.render_publish_at_for_user(reminder,
                                                   "Europe/Bucharest")
      expect(rendered).to eq("2026-06-01T08:00")
    end
  end
end
