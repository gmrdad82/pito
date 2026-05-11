require "rails_helper"

# Phase 26 — 01a. Timezone foundation.
#
# `Timezoned` mixes into `User` to validate `time_zone` against the
# IANA tz set + Rails alias map and expose `#tz` returning the
# resolved `ActiveSupport::TimeZone` instance.
#
# These specs exercise the concern through `User` (its only host
# model) rather than spinning up a throwaway model — that keeps the
# coverage anchored to the real surface the rest of the app reads.
RSpec.describe Timezoned, type: :model do
  describe "validation" do
    it "accepts a canonical IANA zone name" do
      user = build(:user, time_zone: "Europe/Bucharest")
      expect(user).to be_valid, "expected Europe/Bucharest to be valid: #{user.errors.full_messages}"
    end

    it "accepts the UTC sentinel as a Rails alias" do
      user = build(:user, time_zone: "UTC")
      expect(user).to be_valid, "expected UTC alias to be valid: #{user.errors.full_messages}"
    end

    it "accepts the Etc/UTC canonical zero zone" do
      user = build(:user, time_zone: "Etc/UTC")
      expect(user).to be_valid, "expected Etc/UTC to be valid: #{user.errors.full_messages}"
    end

    it "accepts the Pacific/Kiritimati edge zone (UTC+14)" do
      user = build(:user, time_zone: "Pacific/Kiritimati")
      expect(user).to be_valid, "expected Pacific/Kiritimati to be valid: #{user.errors.full_messages}"
    end

    it "accepts the Pacific/Pago_Pago edge zone (UTC-11)" do
      user = build(:user, time_zone: "Pacific/Pago_Pago")
      expect(user).to be_valid, "expected Pacific/Pago_Pago to be valid: #{user.errors.full_messages}"
    end

    it "accepts Asia/Kolkata (UTC+5:30 fractional offset)" do
      user = build(:user, time_zone: "Asia/Kolkata")
      expect(user).to be_valid, "expected Asia/Kolkata to be valid: #{user.errors.full_messages}"
    end

    it "rejects an unknown zone name" do
      user = build(:user, time_zone: "Mars/Olympus_Mons")
      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to include("is not a recognized IANA time zone")
    end

    it "rejects a blank zone" do
      user = build(:user, time_zone: "")
      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to be_present
    end

    it "rejects a nil zone" do
      user = build(:user, time_zone: nil)
      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to be_present
    end

    it "rejects a numeric offset string" do
      user = build(:user, time_zone: "+05:00")
      expect(user).not_to be_valid
      expect(user.errors[:time_zone]).to be_present
    end

    it "rejects whitespace-padded input (no trim semantics on this column)" do
      user = build(:user, time_zone: " Europe/Bucharest ")
      expect(user).not_to be_valid
    end
  end

  describe "#tz" do
    it "returns an ActiveSupport::TimeZone instance for an IANA name" do
      user = build(:user, time_zone: "America/Los_Angeles")
      expect(user.tz).to be_a(ActiveSupport::TimeZone)
      expect(user.tz.tzinfo.name).to eq("America/Los_Angeles")
    end

    it "round-trips an IANA name through the resolved zone" do
      user = build(:user, time_zone: "Pacific/Kiritimati")
      # Kiritimati is UTC+14 — a midnight UTC instant lands at 14:00
      # local on the same calendar date.
      utc_midnight = Time.utc(2026, 6, 1, 0, 0, 0)
      local = utc_midnight.in_time_zone(user.tz)
      expect(local.hour).to eq(14)
      expect(local.day).to eq(1)
    end

    it "honors the half-hour offset for Asia/Kolkata" do
      user = build(:user, time_zone: "Asia/Kolkata")
      utc_noon = Time.utc(2026, 6, 1, 12, 0, 0)
      local = utc_noon.in_time_zone(user.tz)
      expect(local.hour).to eq(17)
      expect(local.min).to eq(30)
    end

    it "falls back to Etc/UTC for an unresolvable stored zone (defensive)" do
      # Bypass validation so we can simulate corruption.
      user = create(:user)
      user.update_column(:time_zone, "Garbage/NotReal")
      expect(user.tz.tzinfo.name).to eq("Etc/UTC")
    end
  end

  describe "ALLOWED_TIME_ZONES" do
    it "includes the IANA canonical names" do
      expect(Timezoned::ALLOWED_TIME_ZONES).to include("Europe/Bucharest")
      expect(Timezoned::ALLOWED_TIME_ZONES).to include("America/Los_Angeles")
      expect(Timezoned::ALLOWED_TIME_ZONES).to include("Asia/Kolkata")
    end

    it "includes the Rails-friendly alias keys" do
      expect(Timezoned::ALLOWED_TIME_ZONES).to include("UTC")
    end

    it "is frozen so accidental membership mutations fail loudly" do
      expect(Timezoned::ALLOWED_TIME_ZONES).to be_frozen
    end
  end
end
