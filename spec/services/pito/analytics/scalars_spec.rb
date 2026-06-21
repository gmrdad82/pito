# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Scalars do
  # Build a scalars row (symbol keys, as AnalyticsClient#scalars returns).
  def row(views:, mins: 0, dur: 0, pct: 0.0, gained: 0, lost: 0, likes: 0, dislikes: 0, comments: 0)
    {
      views: views, estimated_minutes_watched: mins, average_view_duration: dur,
      average_view_percentage: pct, subscribers_gained: gained, subscribers_lost: lost,
      likes: likes, dislikes: dislikes, comments: comments
    }
  end

  # Stub the per-channel YouTube call, dispatching to current/previous rows by the
  # window's start dates so we can exercise trends + multi-channel aggregation.
  def stub_scalars(win, per_channel)
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars) do |_client, channel_id:, start_date:, **|
      rows = per_channel.fetch(channel_id, {})
      if start_date == win.start_date
        rows[:current] || {}
      elsif win.prev_start && start_date == win.prev_start
        rows[:previous] || {}
      else
        {}
      end
    end
  end

  let(:win_28d)      { Pito::Analytics::Window.for("28d", reference_date: Date.current) }
  let(:win_lifetime) { Pito::Analytics::Window.for("lifetime", reference_date: Date.current) }

  describe "single video scope" do
    let(:channel) { create(:channel, :on_connection) }
    let(:video)   { create(:video, channel: channel) }

    it "returns a Result with current+previous per metric and the window label" do
      stub_scalars(win_28d, channel.youtube_channel_id => {
        current:  row(views: 100, mins: 600, dur: 120, pct: 40.0, gained: 5, lost: 1, likes: 10, dislikes: 2, comments: 3),
        previous: row(views: 80,  mins: 480, dur: 100, pct: 35.0, gained: 4, lost: 0, likes: 8,  dislikes: 1, comments: 2)
      })

      result = described_class.for(scope: video, period: "28d")

      expect(result).to be_a(described_class::Result)
      expect(result.label).to eq(win_28d.label)
      expect(result.comparable).to be(true)
      expect(result.metrics[:views]).to eq(current: 100, previous: 80)
      expect(result.metrics[:watched_hours][:current]).to eq(10.0)   # 600 / 60
      expect(result.metrics[:subs_lost]).to eq(current: 1, previous: 0)
      expect(result.metrics[:dislikes][:current]).to eq(2)
    end

    it "defaults to the 28d window when period is blank" do
      stub_scalars(win_28d, channel.youtube_channel_id => { current: row(views: 7) })
      result = described_class.for(scope: video, period: nil)
      expect(result.label).to eq(win_28d.label)
      expect(result.metrics[:views][:current]).to eq(7)
    end
  end

  describe "lifetime window (no baseline)" do
    let(:channel) { create(:channel, :on_connection) }
    let(:video)   { create(:video, channel: channel) }

    it "has comparable=false and nil previous, never querying a prior window" do
      stub_scalars(win_lifetime, channel.youtube_channel_id => { current: row(views: 500) })
      result = described_class.for(scope: video, period: "lifetime")
      expect(result.comparable).to be(false)
      expect(result.metrics[:views]).to eq(current: 500, previous: nil)
    end
  end

  describe "game scope — multi-channel aggregation" do
    let(:ch1)  { create(:channel, :on_connection) }
    let(:ch2)  { create(:channel, :on_connection) }
    let(:game) { create(:game) }

    before do
      create(:video_game_link, video: create(:video, channel: ch1), game: game)
      create(:video_game_link, video: create(:video, channel: ch2), game: game)
    end

    it "sums additive metrics and views-weights the ratio metrics" do
      stub_scalars(win_lifetime,
        ch1.youtube_channel_id => { current: row(views: 100, mins: 600,  dur: 100, pct: 50.0, likes: 10) },
        ch2.youtube_channel_id => { current: row(views: 300, mins: 1800, dur: 200, pct: 30.0, likes: 30) })

      result = described_class.for(scope: game, period: "lifetime")

      expect(result.metrics[:views][:current]).to eq(400)
      expect(result.metrics[:likes][:current]).to eq(40)
      expect(result.metrics[:watched_hours][:current]).to eq(40.0)              # (600+1800)/60
      expect(result.metrics[:avg_view_duration][:current]).to eq(175)          # (100*100 + 200*300)/400
      expect(result.metrics[:avg_viewed_pct][:current]).to eq(35.0)            # (50*100 + 30*300)/400
    end

    it "skips channels needing reauth and aggregates only usable ones" do
      ch2.youtube_connection.update!(needs_reauth: true)
      stub_scalars(win_lifetime,
        ch1.youtube_channel_id => { current: row(views: 100) },
        ch2.youtube_channel_id => { current: row(views: 999) })

      result = described_class.for(scope: game, period: "lifetime")
      expect(result.metrics[:views][:current]).to eq(100)
    end
  end

  describe ":unavailable cases" do
    it "is :unavailable when the video's channel has no connection" do
      video = create(:video, channel: create(:channel))
      expect(described_class.for(scope: video, period: "28d")).to eq(:unavailable)
    end

    it "is :unavailable when the channel needs reauth" do
      channel = create(:channel, youtube_connection: create(:youtube_connection, :needs_reauth))
      video   = create(:video, channel: channel)
      expect(described_class.for(scope: video, period: "28d")).to eq(:unavailable)
    end

    it "is :unavailable when a game has no linked videos" do
      expect(described_class.for(scope: create(:game), period: "28d")).to eq(:unavailable)
    end

    it "is :unavailable (rescued) when the API errors" do
      channel = create(:channel, :on_connection)
      video   = create(:video, channel: channel)
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars).and_raise(StandardError, "boom")
      expect(described_class.for(scope: video, period: "28d")).to eq(:unavailable)
    end
  end
end
