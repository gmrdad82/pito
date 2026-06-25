# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Primitives, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  # Fixed instants so TTL arithmetic and finalization logic are deterministic.
  #
  #   reference_date = 2026-01-15
  #   live_window    = 7d  → start=2026-01-09, end=2026-01-15 (not finalized)
  #   finalized_window = m1 → start=2025-12-01, end=2025-12-31 (finalized: 31d > 7d ago)
  #   now            = 2026-01-15 12:00:00 UTC
  #
  # Time is frozen to `now` for every example so that `Time.current` equals
  # `now`. This ensures that a row stored with `expires_at = now + 1.hour` is
  # correctly seen as live (not expired) when `live?` is checked within the
  # same example.
  let(:reference_date)   { Date.new(2026, 1, 15) }
  let(:now)              { Time.utc(2026, 1, 15, 12, 0, 0) }
  let(:live_window)      { Pito::Analytics::Window.for("7d", reference_date: reference_date) }
  let(:finalized_window) { Pito::Analytics::Window.for("m1", reference_date: reference_date) }

  # Channel with a YouTube connection so AnalyticsClient can be instantiated.
  let(:channel)  { create(:channel, :on_connection) }
  let(:video)    { create(:video, channel: channel) }

  # Freeze time to `now` for every example so Time.current == now.
  # This makes `expires_at = now + 1.hour` appear live when live? checks
  # `expires_at <= Time.current`.
  around do |example|
    travel_to(now) { example.run }
  end

  # Stub the YouTube Analytics API boundary — mirrors the house pattern used in
  # scalars_spec.rb (`allow_any_instance_of`) so we never hit the network.
  def stub_client_scalars(return_value)
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient)
      .to receive(:scalars)
      .and_return(return_value)
  end

  # Convenience: look up the persisted primitive for a video+window combo.
  def persisted_primitive(vid_id, window)
    AnalyticsPrimitive.find_by!(
      video_youtube_id: vid_id,
      report:           "scalars",
      start_date:       window.start_date,
      end_date:         window.end_date
    )
  end

  # ── unsupported report ───────────────────────────────────────────────────────

  describe ".fetch — unsupported report" do
    it "raises ArgumentError for a report that is in REPORTS but not REPORT_METHODS (retention)" do
      expect {
        described_class.fetch(
          groups: [ [ channel, [ video.youtube_video_id ] ] ],
          window: live_window,
          report: "retention",
          now:    now
        )
      }.to raise_error(ArgumentError, /unsupported primitives report.*"retention"/)
    end

    it "raises ArgumentError for a completely unknown report" do
      expect {
        described_class.fetch(
          groups: [ [ channel, [ video.youtube_video_id ] ] ],
          window: live_window,
          report: "bogus",
          now:    now
        )
      }.to raise_error(ArgumentError, /unsupported primitives report/)
    end
  end

  # ── cold fetch + store ───────────────────────────────────────────────────────

  describe ".fetch — cold fetch (no cached row)" do
    let(:raw_metrics) { { views: 500, estimated_minutes_watched: 300 } }

    before do
      expect_any_instance_of(::Channel::Youtube::AnalyticsClient)
        .to receive(:scalars)
        .once
        .and_return(raw_metrics)
    end

    it "calls the YouTube client exactly once" do
      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )
    end

    it "persists an AnalyticsPrimitive row" do
      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )
      expect(
        AnalyticsPrimitive.exists?(
          video_youtube_id: video.youtube_video_id,
          report:           "scalars",
          start_date:       live_window.start_date,
          end_date:         live_window.end_date
        )
      ).to be(true)
    end

    it "returns the metrics hash keyed by youtube_video_id" do
      result = described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )
      expect(result).to have_key(video.youtube_video_id)
    end
  end

  # ── string-key normalisation ─────────────────────────────────────────────────

  describe ".fetch — string-key normalisation" do
    it "converts symbol keys returned by the client into string keys" do
      stub_client_scalars({ views: 100, estimated_minutes_watched: 600 })

      result = described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      metrics = result[video.youtube_video_id]
      expect(metrics).to eq({ "views" => 100, "estimated_minutes_watched" => 600 })
      expect(metrics.keys).to all(be_a(String))
    end

    it "stores string-keyed metrics in the DB row" do
      stub_client_scalars({ views: 42 })

      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      row = persisted_primitive(video.youtube_video_id, live_window)
      expect(row.metrics).to eq({ "views" => 42 })
      expect(row.metrics.keys).to all(be_a(String))
    end
  end

  # ── warm reuse ───────────────────────────────────────────────────────────────

  describe ".fetch — warm reuse (live cached row)" do
    before do
      create(:analytics_primitive,
             video_youtube_id: video.youtube_video_id,
             report:           "scalars",
             period_token:     live_window.token,
             start_date:       live_window.start_date,
             end_date:         live_window.end_date,
             metrics:          { "views" => 999 },
             fetched_at:       now - 30.minutes,
             expires_at:       now + 30.minutes)
    end

    it "does not call the YouTube client" do
      expect_any_instance_of(::Channel::Youtube::AnalyticsClient).not_to receive(:scalars)

      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )
    end

    it "returns the cached metrics" do
      result = described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      expect(result[video.youtube_video_id]).to eq({ "views" => 999 })
    end
  end

  # ── TTL: finalized window ────────────────────────────────────────────────────

  describe ".fetch — TTL for finalized window" do
    it "stores expires_at: nil so the row is frozen forever" do
      stub_client_scalars({ views: 1 })

      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: finalized_window,
        report: "scalars",
        now:    now
      )

      row = persisted_primitive(video.youtube_video_id, finalized_window)
      expect(row.expires_at).to be_nil
      expect(row).to be_frozen
    end
  end

  # ── TTL: live window ─────────────────────────────────────────────────────────

  describe ".fetch — TTL for live window" do
    it "stores expires_at ≈ now + 1 hour" do
      stub_client_scalars({ views: 1 })

      described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      row = persisted_primitive(video.youtube_video_id, live_window)
      expect(row.expires_at).to be_within(1.second).of(now + 1.hour)
    end
  end

  # ── cross-entity reuse ───────────────────────────────────────────────────────

  describe ".fetch — cross-entity reuse (same video_id in two groups)" do
    # Two different channels both listing the same youtube_video_id.
    # The first group triggers a cold fetch and persists the row; the second
    # group finds the warm row and skips the API — so the client is called once.
    # Time is frozen, so the row's expires_at (now + 1h) is still in the future
    # when the second group checks live?.
    let(:channel2) { create(:channel, :on_connection) }

    it "calls the YouTube client only once across groups sharing the same video id" do
      call_count = 0
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient)
        .to receive(:scalars) do
          call_count += 1
          { views: 42 }
        end

      result = described_class.fetch(
        groups: [
          [ channel,  [ video.youtube_video_id ] ],
          [ channel2, [ video.youtube_video_id ] ]
        ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      expect(call_count).to eq(1)
      expect(result[video.youtube_video_id]).to eq({ "views" => 42 })
    end
  end

  # ── RecordNotUnique (concurrent-insert race) ─────────────────────────────────

  describe ".fetch — RecordNotUnique falls back to the winning concurrent row" do
    it "reuses the row inserted by the concurrent worker" do
      # Create the row that a hypothetical concurrent worker already persisted.
      concurrent_row = create(:analytics_primitive,
                              video_youtube_id: video.youtube_video_id,
                              report:           "scalars",
                              period_token:     live_window.token,
                              start_date:       live_window.start_date,
                              end_date:         live_window.end_date,
                              metrics:          { "views" => 77 },
                              fetched_at:       now,
                              expires_at:       now + 1.hour)

      # Simulate a cold read: no warm row visible to our process.
      allow(AnalyticsPrimitive).to receive(:find_by).and_return(nil)

      # find_or_initialize_by returns a record whose save! will race and lose.
      racing = AnalyticsPrimitive.new(
        video_youtube_id: video.youtube_video_id,
        report:           "scalars",
        period_token:     live_window.token,
        start_date:       live_window.start_date,
        end_date:         live_window.end_date
      )
      allow(racing).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
      allow(AnalyticsPrimitive).to receive(:find_or_initialize_by).and_return(racing)

      # The rescue path reads the winner.
      allow(AnalyticsPrimitive).to receive(:find_by!).and_return(concurrent_row)

      stub_client_scalars({ views: 0 })

      result = described_class.fetch(
        groups: [ [ channel, [ video.youtube_video_id ] ] ],
        window: live_window,
        report: "scalars",
        now:    now
      )

      expect(result[video.youtube_video_id]).to eq({ "views" => 77 })
    end
  end
end
