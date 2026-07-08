# frozen_string_literal: true

require "rails_helper"

# Contract for Pito::Mcp::AnalyticsFill — the inline pending-analytics compute.
# The compute SERVICES (Scalars / AnalyzeMetricFill / ChannelDistribution) hit the
# YouTube API, so they are ALWAYS stubbed here; this pins the detection + the
# EventText-friendly rewriting, not the analytics math.
RSpec.describe Pito::Mcp::AnalyticsFill do
  describe "pass-through" do
    it "leaves a non-analytics event untouched" do
      event = { kind: :system, payload: { "table_rows" => [ { cells: [] } ] } }
      expect(described_class.call([ event ])).to eq([ event ])
    end

    it "leaves a READY (non-pending) analytics event untouched" do
      event = { kind: :enhanced, payload: { "analytics" => { "status" => "ready" } } }
      expect(described_class.call([ event ])).to eq([ event ])
    end

    it "tolerates a nil/blank payload" do
      expect(described_class.call([ { kind: :system, payload: nil } ]))
        .to eq([ { kind: :system, payload: nil } ])
    end
  end

  describe "glance (Scalars) family" do
    let(:game) { create(:game, title: "Hollow Knight") }

    let(:metrics) do
      {
        views:             { current: 1234, previous: 1000 },
        watched_hours:     { current: 56.7, previous: 50.0 },
        avg_view_duration: { current: 154,  previous: 140 },
        avg_viewed_pct:    { current: 42.3, previous: 40.0 },
        subs_gained:       { current: 45,   previous: 30 },
        subs_lost:         { current: 3,    previous: 2 },
        likes:             { current: 89,   previous: 70 },
        dislikes:          { current: 4,    previous: 3 },
        comments:          { current: 12,   previous: 10 }
      }
    end
    let(:result) { Pito::Analytics::Scalars::Result.new(metrics: metrics, label: "lifetime", comparable: false) }

    def pending_glance(scope_id: game.id, scope_ids: nil, type: "Game", period: "lifetime")
      marker = { "status" => "pending", "scope_type" => type, "period" => period }
      marker["scope_id"]  = scope_id  if scope_id
      marker["scope_ids"] = scope_ids if scope_ids
      { kind: :enhanced, payload: { "analytics" => marker } }
    end

    before { allow(Pito::Analytics::Scalars).to receive(:for).and_return(result) }

    it "calls Scalars.for with the single loaded record and the marker period" do
      described_class.call([ pending_glance ])
      expect(Pito::Analytics::Scalars).to have_received(:for).with(scope: game, period: "lifetime")
    end

    it "replaces the pending marker with a metrics payload" do
      filled = described_class.call([ pending_glance ]).first
      expect(filled[:payload]).to have_key("metrics")
      expect(filled[:payload]).not_to have_key("analytics")   # scaffold marker gone
    end

    it "projects each scalar as a readable value" do
      m = described_class.call([ pending_glance ]).first[:payload]["metrics"]
      expect(m["views"]).to eq("1234")
      expect(m["likes"]).to eq("89")
      expect(m["watched hours"]).to eq("56.7")
    end

    it "formats avg_view_duration as M:SS and avg_viewed_pct with a percent sign" do
      m = described_class.call([ pending_glance ]).first[:payload]["metrics"]
      expect(m["avg view duration"]).to eq("2:34")
      expect(m["avg viewed pct"]).to eq("42.3%")
    end

    it "builds a heading naming the entity and the period" do
      text = described_class.call([ pending_glance ]).first[:payload]["text"]
      expect(text).to include("Hollow Knight", "lifetime")
    end

    it "loads a multi-id scope set (scope_ids) and passes the Array to Scalars.for" do
      g2 = create(:game, title: "Celeste")
      described_class.call([ pending_glance(scope_id: nil, scope_ids: [ game.id, g2.id ]) ])
      expect(Pito::Analytics::Scalars).to have_received(:for).with(scope: [ game, g2 ], period: "lifetime")
    end

    it "preserves the event kind" do
      expect(described_class.call([ pending_glance ]).first[:kind]).to eq(:enhanced)
    end
  end

  describe "analyze / breakdowns (AnalyzeMetricFill) family" do
    def filled(slot, data)
      Pito::Analytics::AnalyzeMetricFill::Filled.new(cell: {}, raw: { "slot" => slot, "data" => data })
    end

    def no_data
      Pito::Analytics::AnalyzeMetricFill::Filled.new(cell: {}, raw: nil)
    end

    def pending_analyze(metric_keys:, level: "game", ids: [ 3 ], period: "28d", title: "Hollow Knight")
      { kind: :system, payload: { "analyze" => {
        "status" => "pending", "role" => "system", "level" => level, "entity_ids" => ids,
        "period" => period, "title" => title, "metric_keys" => metric_keys
      } } }
    end

    before do
      allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for) do |metric:, **_|
        case metric
        when :views               then filled("charts", { "total" => 1234, "series" => [ 1, 2 ] })
        when :retention           then filled("charts", { "total_pct" => 48.5 })
        when :geography           then filled("bars", [ { "key" => "US", "pct" => 62.0 }, { "key" => "UK", "pct" => 7.3 } ])
        when :day_of_week_heatmap then filled("charts", { "values" => [ 1, 2, 3 ] }) # chart slot, no total
        else no_data
        end
      end
    end

    it "calls AnalyzeMetricFill.for per metric with level / entity_ids / period" do
      described_class.call([ pending_analyze(metric_keys: %w[views]) ])
      expect(Pito::Analytics::AnalyzeMetricFill)
        .to have_received(:for).with(metric: :views, level: "game", entity_ids: [ 3 ], period: "28d")
    end

    it "projects chart metrics as `metrics` totals (retention as a percentage)" do
      payload = described_class.call([ pending_analyze(metric_keys: %w[views retention]) ]).first[:payload]
      expect(payload["metrics"]).to eq("views" => "1234", "retention" => "48.5%")
    end

    it "lays out bar metrics under `bars` for EventText" do
      payload = described_class.call([ pending_analyze(metric_keys: %w[geography]) ]).first[:payload]
      expect(payload["bars"]).to eq("geography" => [ { "key" => "US", "pct" => 62.0 }, { "key" => "UK", "pct" => 7.3 } ])
    end

    it "skips a chart with no scalar total (heatmap) and a no-data metric" do
      payload = described_class.call([ pending_analyze(metric_keys: %w[day_of_week_heatmap unknownmetric]) ]).first[:payload]
      expect(payload).not_to have_key("metrics")
      expect(payload).not_to have_key("bars")
    end

    it "builds a heading from the marker title and period" do
      text = described_class.call([ pending_analyze(metric_keys: %w[views]) ]).first[:payload]["text"]
      expect(text).to include("Hollow Knight", "28d")
    end

    it "renders through EventText to metric lines + a breakdown list" do
      event = described_class.call([ pending_analyze(metric_keys: %w[views geography]) ]).first
      text  = Pito::Mcp::EventText.call([ event ])
      expect(text).to include("- views: 1234", "**geography**", "- US: 62%")
    end
  end

  describe "channel distribution (Game::ChannelDistribution) family" do
    let(:game)    { create(:game, title: "Hades") }
    let(:channel) { create(:channel, title: "Speedrun Central") }
    let(:share)   { Game::ChannelDistribution::Share.new(channel: channel, share: 60, raw: { videos: 3, views: 1500, watch_hours: 20.0 }) }

    def pending_dist(game_id: game.id)
      { kind: :enhanced, payload: { "channel_distribution" => { "status" => "pending", "game_id" => game_id } } }
    end

    before do
      allow(Pito::Recommendations).to receive(:channels_for).and_return([ double("Reco", channel: channel) ])
      allow(Game::ChannelWatchTime).to receive(:hours_for).and_return({})
      allow(Game::ChannelDistribution).to receive(:call).and_return({ nodata: false, shares: [ share ] })
    end

    it "projects covering channels with their share and per-channel counts" do
      text = described_class.call([ pending_dist ]).first[:payload]["text"]
      expect(text).to include("Channels covering Hades:", "60%", "3 vids", "1500 views")
    end

    it "notes when no channel covers the game (nodata)" do
      allow(Game::ChannelDistribution).to receive(:call).and_return({ nodata: true, shares: [] })
      expect(described_class.call([ pending_dist ]).first[:payload]["text"]).to match(/No channels cover/i)
    end

    it "notes when the game no longer exists (never computes shares)" do
      expect(Pito::Recommendations).not_to receive(:channels_for)
      expect(described_class.call([ pending_dist(game_id: 999_999) ]).first[:payload]["text"])
        .to match(/no longer present/i)
    end
  end

  describe "glance — unavailable / missing" do
    let(:game) { create(:game) }

    def pending_glance(scope_id) = { payload: { "analytics" => { "status" => "pending", "scope_type" => "Game", "scope_id" => scope_id, "period" => "lifetime" } } }

    it "notes 'unavailable' when Scalars returns :unavailable (no metrics)" do
      allow(Pito::Analytics::Scalars).to receive(:for).and_return(Pito::Analytics::Scalars::UNAVAILABLE)
      filled = described_class.call([ pending_glance(game.id) ]).first
      expect(filled[:payload]["text"]).to match(/unavailable/i)
      expect(filled[:payload]).not_to have_key("metrics")
    end

    it "notes when the scoped entity no longer exists (never calls Scalars)" do
      expect(Pito::Analytics::Scalars).not_to receive(:for)
      filled = described_class.call([ pending_glance(999_999) ]).first
      expect(filled[:payload]["text"]).to match(/no longer present/i)
    end
  end
end
