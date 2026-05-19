require "rails_helper"

RSpec.describe CompactTimeHelper, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  describe "#compact_time_ago" do
    let(:now) { Time.zone.local(2026, 5, 2, 12, 0, 0) }

    around do |example|
      travel_to(now) { example.run }
    end

    it "returns 'never' for nil" do
      expect(helper.compact_time_ago(nil)).to eq("never")
    end

    # Task #365 (2026-05-18) — the under-one-minute bucket switched
    # from the hardcoded `~60s ago` ceiling to round-down `~Xs ago`
    # emission so a just-finished event reads `~0s ago` instead of
    # the misleading `~60s ago`. See `app/helpers/compact_time_helper.rb`.
    it "returns the rounded-down seconds for anything under one minute (30 seconds ago)" do
      expect(helper.compact_time_ago(30.seconds.ago)).to eq("~30s ago")
    end

    it "returns the rounded-down seconds for anything under one minute (just under 60s)" do
      expect(helper.compact_time_ago(59.seconds.ago)).to eq("~59s ago")
    end

    it "returns minute-level format for 5 minutes ago" do
      expect(helper.compact_time_ago(5.minutes.ago)).to eq("~5m ago")
    end

    it "returns hour-level format for 4 hours ago" do
      expect(helper.compact_time_ago(4.hours.ago)).to eq("~4h ago")
    end

    it "returns day-level format for 3 days ago" do
      expect(helper.compact_time_ago(3.days.ago)).to eq("~3d ago")
    end

    it "returns month-level format for 6 months ago" do
      # Use seconds directly to avoid calendar drift across month boundaries.
      expect(helper.compact_time_ago(Time.current - (6 * 2_592_000))).to eq("~6mo ago")
    end

    it "returns year-level format for 2 years ago" do
      expect(helper.compact_time_ago(Time.current - (2 * 31_536_000))).to eq("~2yr ago")
    end

    it "uses minute boundary at exactly 60 seconds" do
      expect(helper.compact_time_ago(60.seconds.ago)).to eq("~1m ago")
    end

    it "uses hour boundary at exactly 60 minutes" do
      expect(helper.compact_time_ago(60.minutes.ago)).to eq("~1h ago")
    end

    it "uses day boundary at exactly 24 hours" do
      expect(helper.compact_time_ago(24.hours.ago)).to eq("~1d ago")
    end
  end
end
