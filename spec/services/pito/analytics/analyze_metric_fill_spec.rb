# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::AnalyzeMetricFill do
  # Use doubles for Channel so no DB touch is needed in the cell-logic tests.
  # `groups_for` is stubbed in the shared before block; individual tests override
  # it when they need different group shapes.
  let(:channel) { instance_double(::Channel, id: 1, subscriber_count: 0) }
  let(:groups)  { [ [ channel, :channel ] ] }

  before { allow(described_class).to receive(:groups_for).and_return(groups) }

  # Assertions target the renderable CELL; Filled#raw (the marker stash entry)
  # gets its own examples below.
  def call(metric:, level: "channel", entity_ids: [ 1 ], period: "28d")
    described_class.for(metric:, level:, entity_ids:, period:).cell
  end

  def daily_result(dates: [ Date.new(2026, 6, 1) ], series: [ 100 ], total: 100)
    Pito::Analytics::DailySeries::Result.new(dates:, series:, total:)
  end

  # ── AREA metric (views) ────────────────────────────────────────────────────────

  describe "area metric (:views)" do
    before do
      allow(Pito::Analytics::DailySeries).to receive(:for).and_return(daily_result)
      allow(Pito::MessageBuilder::Analyze::Message)
        .to receive(:render_chart_caption).and_return("<span>41K▲</span>".html_safe)
    end

    it "returns chart + series + caption" do
      result = call(metric: :views)

      expect(result[:chart]).to eq(:views)
      expect(result[:series]).to eq([ 100 ])
      expect(result[:caption]).to be_present
      expect(result[:target_daily]).to be_a(Float)
    end

    it "carries dates as ISO-8601 strings" do
      expect(call(metric: :views)[:dates]).to eq([ "2026-06-01" ])
    end

    it "defaults trend to true (standard daily chart has no explicit trend key)" do
      expect(call(metric: :views)[:trend]).to be true
    end
  end

  # ── HEART (likes) ─────────────────────────────────────────────────────────────

  describe "likes metric (HEART)" do
    let(:likes_data) { [ { score: 90.0, color: :red, likes: 900, dislikes: 100 } ] }
    let(:likes_marker) do
      {
        "hearts"  => [ { "score" => 90.0, "color" => "red", "likes" => 900, "dislikes" => 100 } ],
        "caption" => "<span>Likes caption</span>"
      }
    end

    before do
      allow(Pito::Analytics::LikesHearts).to receive(:for).and_return(likes_data)
      allow(Pito::MessageBuilder::Analyze::Message).to receive(:likes_marker).and_return(likes_marker)
    end

    it "returns heart array + caption" do
      result = call(metric: :likes)

      expect(result[:heart]).to be_an(Array).and(be_present)
      expect(result[:heart].first).to include(score: 90.0, color: :red)
      expect(result[:caption]).to be_present
    end
  end

  # ── BAR metric (subscribed_status) ────────────────────────────────────────────

  describe "bar metric (:subscribed_status)" do
    let(:bar_rows) do
      [ { key: "UNSUBSCRIBED", pct: 70.0 }, { key: "SUBSCRIBED", pct: 30.0 } ]
    end

    before do
      allow(Pito::Analytics::Breakdown).to receive(:for).and_return(bar_rows)
      allow(Pito::MessageBuilder::Analyze::Message)
        .to receive(:render_bar_caption).and_return("<span>bar cap</span>".html_safe)
    end

    it "returns bars array + caption" do
      result = call(metric: :subscribed_status)

      expect(result[:bars]).to be_an(Array).and(be_present)
      expect(result[:bars].first).to include(:label, :color, :pct, :value_label)
      expect(result[:caption]).to be_present
    end

    it "always uses the LIFETIME window for bar breakdowns regardless of the passed period" do
      call(metric: :subscribed_status, period: "7d")

      expect(Pito::Analytics::Breakdown).to have_received(:for).with(
        hash_including(window: satisfy { |w| w.token == "lifetime" })
      )
    end
  end

  # ── comments (area chart) ─────────────────────────────────────────────────────

  describe "comments (area chart)" do
    before do
      allow(Pito::Analytics::DailySeries).to receive(:for).and_return(daily_result)
      allow(Pito::Analytics::DailySeries).to receive(:for)
        .with(hash_including(metric: "comments")).and_return(daily_result(series: [ 3, 4, 5 ], total: 12))
    end

    it "returns a comments area-chart cell (daily series folded from the comments column)" do
      result = call(metric: :comments)

      expect(result[:chart]).to eq(:comments)
      expect(result[:series]).to eq([ 3, 4, 5 ])
      expect(result[:caption]).to be_present
    end
  end

  # ── retention (area chart, Item 25) ───────────────────────────────────────────

  describe "retention (area chart)" do
    before do
      allow(Pito::Analytics::RetentionSeries).to receive(:for).and_return(
        Pito::Analytics::RetentionSeries::Result.new(series: [ 80.0, 60.0, 40.0 ], total_pct: 27.9, rel_performance: 0.6)
      )
    end

    it "returns a retention area-chart cell (series + own caption), lifetime, no trend" do
      result = call(metric: :retention, level: "vid")

      expect(result[:chart]).to eq(:retention)
      expect(result[:series]).to eq([ 80.0, 60.0, 40.0 ])
      expect(result[:caption]).to be_present
      expect(result[:trend]).to be false
      expect(result[:reference_token]).to eq("lifetime")
    end
  end

  # ── day-of-week heatmap (Item 30) ─────────────────────────────────────────────

  describe "day_of_week_heatmap" do
    it "returns a heatmap cell with the 7-weekday values + caption" do
      allow(Pito::Analytics::WeekdaySeries).to receive(:for).and_return(
        Pito::Analytics::WeekdaySeries::Result.new(values: [ 10.0, 20.0, 5.0, 30.0, 25.0, 40.0, 15.0 ])
      )
      result = call(metric: :day_of_week_heatmap)

      expect(result[:heatmap]).to eq(:day_of_week_heatmap)
      expect(result[:values]).to eq([ 10.0, 20.0, 5.0, 30.0, 25.0, 40.0, 15.0 ])
      expect(result[:caption]).to be_present
    end

    it "returns no_data when the week is empty (all zero)" do
      allow(Pito::Analytics::WeekdaySeries).to receive(:for).and_return(
        Pito::Analytics::WeekdaySeries::Result.new(values: Array.new(7, 0.0))
      )
      expect(call(metric: :day_of_week_heatmap)[:no_data]).to be true
    end
  end

  # ── fault isolation ───────────────────────────────────────────────────────────

  describe "fault isolation" do
    it "returns no_data when groups are empty (no usable channel)" do
      allow(described_class).to receive(:groups_for).and_return([])
      result = call(metric: :views)

      expect(result[:no_data]).to be true
    end

    it "returns no_data and does not raise when a data service errors" do
      allow(Pito::Analytics::DailySeries).to receive(:for).and_raise(StandardError, "API down")

      expect { call(metric: :views) }.not_to raise_error
      expect(call(metric: :views)[:no_data]).to be true
    end

    it "returns no_data when LikesHearts returns nil (no ratings data)" do
      allow(Pito::Analytics::LikesHearts).to receive(:for).and_return(nil)
      result = call(metric: :likes)

      expect(result[:no_data]).to be true
    end

    it "returns no_data when Breakdown returns empty rows" do
      allow(Pito::Analytics::Breakdown).to receive(:for).and_return([])
      result = call(metric: :subscribed_status)

      expect(result[:no_data]).to be true
    end
  end
end
