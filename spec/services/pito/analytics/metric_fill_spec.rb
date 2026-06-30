# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricFill do
  let!(:channel) { create(:channel, :on_connection) }
  let!(:video)   { create(:video, channel: channel, title: "Boss Fight") }

  let(:client) { instance_double(Channel::Youtube::AnalyticsClient) }

  before { allow(Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client) }

  # Route query() by shape: the daily (dimension: "day") call returns the series
  # rows; the no-dimension call returns the single aggregate row.
  def stub_query(scalar_row:, daily_rows:)
    allow(client).to receive(:query) do |dimensions: nil, **_|
      dimensions == "day" ? daily_rows : [ scalar_row ]
    end
  end

  describe "dedicated per-metric requests" do
    it "uses a metric-scoped `metrics:` string per key (one request, not the shared all-metrics fetch)" do
      stub_query(scalar_row: { views: 10 }, daily_rows: [])
      described_class.for(scope: video, period: "28d", key: "views")
      expect(client).to have_received(:query).with(hash_including(metrics: "views")).at_least(:once)
    end
  end

  describe "views" do
    it "folds the aggregate scalar and the day-series" do
      stub_query(scalar_row: { views: 100 },
                 daily_rows: [ { day: "2026-01-02", views: 60 }, { day: "2026-01-01", views: 40 } ])
      cell = described_class.for(scope: video, period: "28d", key: "views")
      expect(cell.result.metrics[:views][:current]).to eq(100)
      expect(cell.series[:views]).to eq([ 40, 60 ]) # sorted by day
    end
  end

  describe "watched_hours" do
    it "converts estimated minutes to hours" do
      stub_query(scalar_row: { estimated_minutes_watched: 750 }, daily_rows: [])
      cell = described_class.for(scope: video, period: "28d", key: "watched_hours")
      expect(cell.result.metrics[:watched_hours][:current]).to eq(12.5)
    end
  end

  describe "subs_net" do
    it "folds gained and lost separately for the split cell" do
      stub_query(scalar_row: { subscribers_gained: 20, subscribers_lost: 9 },
                 daily_rows: [ { day: "2026-01-01", subscribers_gained: 5, subscribers_lost: 2 } ])
      cell = described_class.for(scope: video, period: "28d", key: "subs_net")
      expect(cell.result.metrics[:subs_gained][:current]).to eq(20)
      expect(cell.result.metrics[:subs_lost][:current]).to eq(9)
      expect(cell.series[:subs]).to eq([ 3 ]) # net per day
    end
  end

  describe "likes" do
    it "folds likes and dislikes separately for the split cell" do
      stub_query(scalar_row: { likes: 210, dislikes: 4 },
                 daily_rows: [ { day: "2026-01-01", likes: 7 } ])
      cell = described_class.for(scope: video, period: "28d", key: "likes")
      expect(cell.result.metrics[:likes][:current]).to eq(210)
      expect(cell.result.metrics[:dislikes][:current]).to eq(4)
      expect(cell.series[:likes]).to eq([ 7 ])
    end
  end

  describe "avg_view_duration" do
    it "views-weights the scalar" do
      stub_query(scalar_row: { average_view_duration: 200, views: 100 }, daily_rows: [])
      cell = described_class.for(scope: video, period: "28d", key: "avg_view_duration")
      expect(cell.result.metrics[:avg_view_duration][:current]).to eq(200)
    end
  end

  describe "fault isolation / unavailability" do
    it "returns UNAVAILABLE when the scope has no usable channel" do
      allow(Pito::Analytics::Scalars).to receive(:channel_groups).and_return([])
      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(Pito::Analytics::MetricFill::UNAVAILABLE)
    end

    it "returns UNAVAILABLE (not raise) when the dedicated request errors" do
      allow(client).to receive(:query).and_raise(RuntimeError, "API timeout")
      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(Pito::Analytics::MetricFill::UNAVAILABLE)
    end

    it "returns UNAVAILABLE (no-data, not a folded 0) when the request comes back empty" do
      allow(client).to receive(:query).and_return([])
      expect(described_class.for(scope: video, period: "28d", key: "views"))
        .to eq(Pito::Analytics::MetricFill::UNAVAILABLE)
    end
  end
end
