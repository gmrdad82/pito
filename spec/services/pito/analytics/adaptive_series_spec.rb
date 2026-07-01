# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::AdaptiveSeries do
  # Stub DailySeries.primitives_daily so no YouTube calls are made.
  def stub_primitives(daily_data)
    allow(Pito::Analytics::Primitives).to receive(:fetch)
      .with(hash_including(report: "daily")).and_return(daily_data)
  end

  def window(token, ref: Date.new(2026, 6, 28))
    Pito::Analytics::Window.for(token, reference_date: ref)
  end

  # ── Bucketing selection ──────────────────────────────────────────────────────

  describe ".bucket_dates" do
    it "returns daily buckets (one date each) for ≤ 30 days" do
      dates = (Date.new(2026, 6, 1)..Date.new(2026, 6, 28)).to_a
      buckets = described_class.bucket_dates(dates, 28)
      expect(buckets.size).to eq(28)
      expect(buckets.first).to eq([ Date.new(2026, 6, 1) ])
    end

    it "returns weekly buckets for 31–90 days" do
      dates = (Date.new(2026, 4, 1)..Date.new(2026, 6, 28)).to_a  # ~89 days
      buckets = described_class.bucket_dates(dates, dates.size)
      # Each bucket is one ISO week; should be roughly ceil(89/7) ≈ 13 weeks
      expect(buckets.size).to be_between(12, 14)
      # Each bucket covers 7 days (except possibly the last)
      expect(buckets.first.size).to be_between(1, 7)
      # All dates in each bucket share the same cweek + cwyear
      buckets.each do |b|
        expect(b.map { |d| [ d.cwyear, d.cweek ] }.uniq.size).to eq(1)
      end
    end

    it "returns monthly buckets for > 90 days" do
      dates = (Date.new(2025, 7, 1)..Date.new(2026, 6, 28)).to_a  # ~362 days
      buckets = described_class.bucket_dates(dates, dates.size)
      expect(buckets.size).to eq(12)  # Jul '25 through Jun '26
      # All dates in each bucket share the same year+month
      buckets.each do |b|
        expect(b.map { |d| [ d.year, d.month ] }.uniq.size).to eq(1)
      end
    end

    it "returns a single bucket for a 1-day window" do
      dates = [ Date.new(2026, 6, 28) ]
      buckets = described_class.bucket_dates(dates, 1)
      expect(buckets.size).to eq(1)
      expect(buckets.first).to eq([ Date.new(2026, 6, 28) ])
    end

    it "boundary: 30 days → daily, 31 days → weekly" do
      dates_30 = (1..30).map { |i| Date.new(2026, 5, 1) + (i - 1) }
      dates_31 = (1..31).map { |i| Date.new(2026, 5, 1) + (i - 1) }
      expect(described_class.bucket_dates(dates_30, 30).size).to eq(30)
      # 31 days starting May 1 spans several ISO weeks
      expect(described_class.bucket_dates(dates_31, 31).size).to be < 31
    end

    it "boundary: 90 days → weekly, 91 days → monthly" do
      # 91 days starting Jan 1 spans 4 months (Jan/Feb/Mar/Apr)
      dates_91 = (0..90).map { |i| Date.new(2026, 1, 1) + i }
      buckets = described_class.bucket_dates(dates_91, 91)
      expect(buckets.size).to eq(4)
    end
  end

  # ── Per-bucket value (views-weighted avg of YouTube's per-day average) ───────
  # AdaptiveSeries now PULLS YouTube's per-day average_view_duration and
  # VIEWS-WEIGHTS it across the scope's videos (Σ(value×views)/Σviews) — it no
  # longer derives it from estimated_minutes_watched.

  describe ".for — computed series and total" do
    it "views-weights YouTube's per-day average_view_duration for a short window" do
      w = window("7d")
      day0 = w.start_date

      # Two videos on the same day; weighted: (6×100 + 4×150)/10 = 120s
      stub_primitives(
        "vidA" => [ { "day" => day0.to_s, "views" => 6, "average_view_duration" => 100 } ],
        "vidB" => [ { "day" => day0.to_s, "views" => 4, "average_view_duration" => 150 } ]
      )
      result = described_class.for(groups: [], window: w)

      expect(result.series.first).to be_within(0.1).of(120.0)
      # Remaining 6 days have no data → 0.0
      expect(result.series[1..].sum).to eq(0.0)
      expect(result.total).to be_within(0.1).of(120.0)
    end

    it "returns 0.0 for buckets with no views (avoids division-by-zero)" do
      w = window("7d")
      stub_primitives({})  # no data
      result = described_class.for(groups: [], window: w)
      expect(result.series).to all(eq(0.0))
      expect(result.total).to eq(0.0)
    end

    it "computes monthly buckets for a >90 day window (1y token spans 12 months)" do
      w = window("1y")
      first_day = w.start_date
      stub_primitives(
        "vid" => [
          {
            "day"                   => first_day.to_s,
            "views"                 => 10,
            "average_view_duration" => 180
          }
        ]
      )
      result = described_class.for(groups: [], window: w)
      # 1y ≈ 365 days → monthly bucketing → 12 or 13 months
      expect(result.series.size).to be_between(12, 13)
      # First month has data: YouTube's average_view_duration = 180s
      expect(result.series.first).to be_within(0.1).of(180.0)
      expect(result.series[1..]).to all(eq(0.0))
    end

    it "views-weights the average across multiple videos per day" do
      w = window("7d")
      day = w.start_date

      stub_primitives(
        "vidA" => [ { "day" => day.to_s, "views" => 100, "average_view_duration" => 120 } ],
        "vidB" => [ { "day" => day.to_s, "views" => 100, "average_view_duration" => 60 } ]
      )
      result = described_class.for(groups: [], window: w)
      # weighted: (100×120 + 100×60)/200 = 90s
      expect(result.series.first).to be_within(0.1).of(90.0)
      expect(result.total).to be_within(0.1).of(90.0)
    end

    it "overall total is Σ(value×views) / Σ(views), not the mean of bucket values" do
      w = window("7d")
      d0 = w.start_date
      d1 = d0 + 1

      stub_primitives(
        "vid" => [
          { "day" => d0.to_s, "views" => 100, "average_view_duration" => 60 },
          { "day" => d1.to_s, "views" => 10,  "average_view_duration" => 600 }
        ]
      )
      result = described_class.for(groups: [], window: w)
      # Bucket 0: 60s ; Bucket 1: 600s ; mean of buckets = 330s (WRONG)
      # Weighted total = (100×60 + 10×600)/110 ≈ 109.1s (correct)
      expect(result.series[0]).to be_within(0.1).of(60.0)
      expect(result.series[1]).to be_within(0.1).of(600.0)
      expect(result.total).to be_within(1.0).of((100 * 60 + 10 * 600) / 110.0)
    end

    it "views-weights average_view_percentage when value_key: :average_view_percentage" do
      w = window("7d")
      day = w.start_date
      stub_primitives(
        "vidA" => [ { "day" => day.to_s, "views" => 3, "average_view_percentage" => 40.0 } ],
        "vidB" => [ { "day" => day.to_s, "views" => 1, "average_view_percentage" => 80.0 } ]
      )
      result = described_class.for(groups: [], window: w, value_key: :average_view_percentage)
      # weighted: (3×40 + 1×80)/4 = 50%
      expect(result.series.first).to be_within(0.1).of(50.0)
      expect(result.total).to be_within(0.1).of(50.0)
    end

    it "tolerates symbol keys in the raw primitive rows" do
      w = window("7d")
      stub_primitives("vid" => [ { day: w.start_date, views: 5, average_view_duration: 120 } ])
      result = described_class.for(groups: [], window: w)
      expect(result.series.first).to be_within(0.1).of(120.0)
    end

    it "ignores rows with unparseable day keys" do
      w = window("7d")
      stub_primitives("vid" => [ { "day" => "not-a-date", "views" => 99, "average_view_duration" => 99 } ])
      result = described_class.for(groups: [], window: w)
      expect(result.total).to eq(0.0)
    end

    # ── dates: field (ACL6) — representative first-of-bucket dates ───────────

    it "returns dates parallel to series (first date of each bucket)" do
      w      = window("7d")  # 7-day window → daily buckets → 7 buckets
      stub_primitives({})
      result = described_class.for(groups: [], window: w)
      # One date per bucket, parallel to series
      expect(result.dates.size).to eq(result.series.size)
      # Each is a Date
      expect(result.dates).to all(be_a(Date))
      # First date = start of the window
      expect(result.dates.first).to eq(w.start_date)
    end

    it "returns one date per monthly bucket for a > 90 day window" do
      w = window("1y")
      stub_primitives({})
      result = described_class.for(groups: [], window: w)
      # One date per bucket (12–13 monthly buckets for ~1 year)
      expect(result.dates.size).to eq(result.series.size)
      expect(result.dates.size).to be_between(12, 13)
      # Each date is a Date and within the window
      expect(result.dates).to all(be_a(Date))
      # Dates are in ascending order (each bucket starts after the previous)
      expect(result.dates).to eq(result.dates.sort)
    end
  end
end
