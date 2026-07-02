# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricFill do
  let!(:channel) { create(:channel, :on_connection) }
  let!(:video)   { create(:video, channel: channel, title: "Boss Fight") }

  let(:window) { Pito::Analytics::Window.for("28d", reference_date: Date.current) }
  let(:client) { instance_double(Channel::Youtube::AnalyticsClient) }

  before { allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client) }

  # Cold-path client stubs: Primitives calls the report methods (scalars/daily)
  # per cold subject. Symbol-keyed like the real client; Primitives stringifies
  # on store, so folds always see string keys.
  def stub_reports(scalar_row: {}, daily_rows: [])
    allow(client).to receive(:scalars).and_return(scalar_row)
    allow(client).to receive(:daily).and_return(daily_rows)
  end

  # Warm-path seeding: a (scalars, daily) primitive pair for a subject over the
  # spec window — string-keyed, exactly as the jsonb round-trip stores them.
  def seed_warm(subject_id, scalar: {}, daily: [])
    create(:analytics_primitive, video_youtube_id: subject_id, report: "scalars",
           start_date: window.start_date, end_date: window.end_date,
           period_token: "28d", metrics: scalar, expires_at: 1.hour.from_now)
    create(:analytics_primitive, video_youtube_id: subject_id, report: "daily",
           start_date: window.start_date, end_date: window.end_date,
           period_token: "28d", metrics: daily, expires_at: 1.hour.from_now)
  end

  describe "folding from the shared primitives (the API-call collapse)" do
    it "serves ALL five glance metrics from ONE scalars + ONE daily fetch" do
      stub_reports(
        scalar_row: { views: 100, estimated_minutes_watched: 750, average_view_duration: 200,
                      subscribers_gained: 20, subscribers_lost: 9, likes: 210, dislikes: 4 },
        daily_rows: [ { day: "2026-01-01", views: 40, estimated_minutes_watched: 60,
                        average_view_duration: 100, subscribers_gained: 5, subscribers_lost: 2, likes: 7 } ]
      )

      %w[views watched_hours avg_view_duration subs_net likes].each do |key|
        expect(described_class.for(scope: video, period: "28d", key:)).to be_a(described_class::Cell)
      end

      expect(client).to have_received(:scalars).once
      expect(client).to have_received(:daily).once
    end

    it "folds every metric with ZERO client calls when the primitives are warm" do
      seed_warm(video.youtube_video_id,
                scalar: { "views" => 100, "estimated_minutes_watched" => 750,
                          "average_view_duration" => 200, "subscribers_gained" => 20,
                          "subscribers_lost" => 9, "likes" => 210, "dislikes" => 4 },
                daily:  [ { "day" => "2026-01-01", "views" => 40, "likes" => 7,
                            "subscribers_gained" => 5, "subscribers_lost" => 2 } ])

      cell = described_class.for(scope: video, period: "28d", key: "views")

      expect(cell.result.metrics[:views][:current]).to eq(100)
      # Warm rows never reach the client — not even instantiation.
      expect(Channel::Youtube::AnalyticsClient).not_to have_received(:new)
    end
  end

  describe "scalar + series folds" do
    it "folds views scalar and the day-series sorted by day" do
      stub_reports(scalar_row: { views: 100 },
                   daily_rows: [ { day: "2026-01-02", views: 60 }, { day: "2026-01-01", views: 40 } ])
      cell = described_class.for(scope: video, period: "28d", key: "views")

      expect(cell.result.metrics[:views][:current]).to eq(100)
      expect(cell.series[:views]).to eq([ 40, 60 ])
    end

    it "converts estimated minutes to hours" do
      stub_reports(scalar_row: { estimated_minutes_watched: 750 })
      cell = described_class.for(scope: video, period: "28d", key: "watched_hours")

      expect(cell.result.metrics[:watched_hours][:current]).to eq(12.5)
    end

    it "folds gained and lost separately for the subs split cell" do
      stub_reports(scalar_row: { subscribers_gained: 20, subscribers_lost: 9 },
                   daily_rows: [ { day: "2026-01-01", subscribers_gained: 5, subscribers_lost: 2 } ])
      cell = described_class.for(scope: video, period: "28d", key: "subs_net")

      expect(cell.result.metrics[:subs_gained][:current]).to eq(20)
      expect(cell.result.metrics[:subs_lost][:current]).to eq(9)
      expect(cell.series[:subs]).to eq([ 3 ])
    end

    it "folds likes and dislikes separately for the likes split cell" do
      stub_reports(scalar_row: { likes: 210, dislikes: 4 },
                   daily_rows: [ { day: "2026-01-01", likes: 7 } ])
      cell = described_class.for(scope: video, period: "28d", key: "likes")

      expect(cell.result.metrics[:likes][:current]).to eq(210)
      expect(cell.result.metrics[:dislikes][:current]).to eq(4)
      expect(cell.series[:likes]).to eq([ 7 ])
    end

    it "views-weights avg_view_duration across subjects sharing a day (never re-derived)" do
      video2 = create(:video, channel: channel, title: "Boss Fight II")
      game   = create(:game)
      create(:video_game_link, game:, video:)
      create(:video_game_link, game:, video: video2)
      seed_warm(video.youtube_video_id,
                scalar: { "average_view_duration" => 100, "views" => 30 },
                daily:  [ { "day" => "2026-01-01", "average_view_duration" => 100, "views" => 30 } ])
      seed_warm(video2.youtube_video_id,
                scalar: { "average_view_duration" => 200, "views" => 10 },
                daily:  [ { "day" => "2026-01-01", "average_view_duration" => 200, "views" => 10 },
                          { "day" => "2026-01-02", "average_view_duration" => 90, "views" => 0 } ])

      cell = described_class.for(scope: game, period: "28d", key: "avg_view_duration")

      expect(cell.result.metrics[:avg_view_duration][:current]).to eq(125) # (100×30 + 200×10)/40
      expect(cell.series[:avg_view_duration]).to eq([ 125, 0 ])            # 0-view day → 0
    end
  end

  describe "channel scope" do
    it "uses ONE channel-wide subject (videos: nil), not a per-vid sum" do
      stub_reports(scalar_row: { views: 500 }, daily_rows: [])

      cell = described_class.for(scope: channel, period: "28d", key: "views")

      expect(cell.result.metrics[:views][:current]).to eq(500)
      expect(client).to have_received(:scalars)
        .with(hash_including(channel_id: channel.youtube_channel_id, videos: nil))
      expect(AnalyticsPrimitive.find_by(video_youtube_id: channel.youtube_channel_id, report: "scalars")).to be_present
    end
  end

  describe "likes daily require_keys (0.9.0 metric addition)" do
    it "refetches a warm daily row that predates the likes key — once" do
      seed_warm(video.youtube_video_id,
                scalar: { "likes" => 210, "dislikes" => 4 },
                daily:  [ { "day" => "2026-01-01", "views" => 40 } ]) # no "likes" key
      allow(client).to receive(:daily)
        .and_return([ { day: "2026-01-01", views: 40, likes: 7 } ])

      cell = described_class.for(scope: video, period: "28d", key: "likes")

      expect(cell.series[:likes]).to eq([ 7 ])
      expect(client).to have_received(:daily).once
      row = AnalyticsPrimitive.find_by(video_youtube_id: video.youtube_video_id, report: "daily")
      expect(row.metrics.first).to have_key("likes")
    end
  end

  describe "fault isolation / unavailability" do
    it "returns UNAVAILABLE when the scope has no usable channel" do
      allow(Pito::Analytics::Scalars).to receive(:channel_groups).and_return([])

      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(described_class::UNAVAILABLE)
    end

    it "returns UNAVAILABLE (not raise) when the cold fetch errors" do
      allow(client).to receive(:scalars).and_raise(RuntimeError, "API timeout")

      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(described_class::UNAVAILABLE)
    end

    it "returns UNAVAILABLE (no-data, not a folded 0) when scalars come back empty" do
      stub_reports(scalar_row: {}, daily_rows: [])

      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(described_class::UNAVAILABLE)
    end
  end
end
