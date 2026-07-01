# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::GlanceSeries do
  let(:scope)  { instance_double(::Channel) }
  let(:groups) { [ [ instance_double(::Channel), :channel ] ] }

  def stub_daily(by_metric, daily_rows: {})
    allow(Pito::Analytics::Scalars).to receive(:channel_groups).with(scope).and_return(groups)
    allow(Pito::Analytics::DailySeries).to receive(:for) do |metric:, **|
      Pito::Analytics::DailySeries::Result.new(dates: [], series: by_metric.fetch(metric, []), total: 0)
    end
    # avg_view_duration now PULLS YouTube's per-day average_view_duration via
    # primitives_daily (Primitives.fetch report:"daily"), not DailySeries.for.
    allow(Pito::Analytics::Primitives).to receive(:fetch)
      .with(hash_including(report: "daily")).and_return(daily_rows)
  end

  it "returns day-series for views, watched_hours (÷60), net subs, and likes" do
    stub_daily({
      "views"                     => [ 10, 20, 30 ],
      "estimated_minutes_watched" => [ 60, 120, 180 ],
      "subscribers_gained"        => [ 5, 6, 7 ],
      "subscribers_lost"          => [ 1, 2, 3 ],
      "likes"                     => [ 2, 4, 6 ]
    })
    result = described_class.for(scope:, period: "28d")

    expect(result[:views]).to eq([ 10, 20, 30 ])
    expect(result[:watched_hours]).to eq([ 1.0, 2.0, 3.0 ]) # minutes ÷ 60
    expect(result[:subs]).to eq([ 4, 4, 4 ])                # gained − lost
    expect(result[:likes]).to eq([ 2, 4, 6 ])
  end

  it "pulls YouTube's per-day average_view_duration (views-weighted), not a derivation" do
    ref  = Date.current
    win  = Pito::Analytics::Window.for("7d", reference_date: ref)
    day0 = win.start_date
    stub_daily(
      {},
      daily_rows: {
        "vidA" => [ { "day" => day0.to_s, "views" => 6, "average_view_duration" => 100 } ],
        "vidB" => [ { "day" => day0.to_s, "views" => 4, "average_view_duration" => 150 } ]
      }
    )
    result = described_class.for(scope:, period: "7d")
    # Day 0 weighted: (6×100 + 4×150)/10 = 120s; other days 0.
    expect(result[:avg_view_duration].first).to eq(120)
    expect(result[:avg_view_duration][1..].sum).to eq(0)
  end

  it "returns {} when the scope has no usable channel group" do
    allow(Pito::Analytics::Scalars).to receive(:channel_groups).with(scope).and_return([])
    expect(described_class.for(scope:, period: "28d")).to eq({})
  end

  it "rescues a fetch error to {} (cell falls back to scalar-only)" do
    allow(Pito::Analytics::Scalars).to receive(:channel_groups).and_raise(StandardError, "boom")
    expect(described_class.for(scope:, period: "7d")).to eq({})
  end
end
