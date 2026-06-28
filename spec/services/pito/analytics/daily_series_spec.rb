# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::DailySeries do
  let(:window) { Pito::Analytics::Window.for("7d", reference_date: Date.new(2026, 6, 8)) }
  let(:day0)   { window.start_date }

  def stub_daily(map)
    allow(Pito::Analytics::Primitives).to receive(:fetch)
      .with(hash_including(report: "daily")).and_return(map)
  end

  it "sums views per day across subjects and 0-fills missing days" do
    stub_daily(
      "vidA" => [ { "day" => day0.to_s, "views" => 5 }, { "day" => (day0 + 1).to_s, "views" => 3 } ],
      "vidB" => [ { "day" => day0.to_s, "views" => 2 } ]
    )
    result = described_class.for(groups: [], window:)

    expect(result.dates.first).to eq(day0)
    expect(result.dates.size).to eq((window.start_date..window.end_date).count)
    expect(result.series.first).to eq(7)  # 5 + 2 on day0
    expect(result.series[1]).to eq(3)
    expect(result.series.last).to eq(0)   # later day → 0-filled
    expect(result.total).to eq(10)
  end

  it "folds a different metric when asked" do
    stub_daily("vidA" => [ { "day" => day0.to_s, "views" => 5, "estimated_minutes_watched" => 40 } ])
    result = described_class.for(groups: [], window:, metric: "estimated_minutes_watched")

    expect(result.series.first).to eq(40)
    expect(result.total).to eq(40)
  end

  it "returns an all-zero series + zero total when there is no data" do
    stub_daily({})
    result = described_class.for(groups: [], window:)

    expect(result.series).to all(eq(0))
    expect(result.total).to eq(0)
  end

  it "tolerates symbol keys and Date day values" do
    stub_daily("vidA" => [ { day: day0, views: 9 } ])
    result = described_class.for(groups: [], window:)

    expect(result.series.first).to eq(9)
  end

  it "ignores rows with an unparseable day" do
    stub_daily("vidA" => [ { "day" => "not-a-date", "views" => 99 } ])
    result = described_class.for(groups: [], window:)

    expect(result.total).to eq(0)
  end
end
