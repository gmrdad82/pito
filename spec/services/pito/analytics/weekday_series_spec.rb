# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::WeekdaySeries do
  # Stub the daily primitives (Primitives.fetch report:"daily") so no YouTube call.
  def stub_daily(rows)
    allow(Pito::Analytics::Primitives).to receive(:fetch)
      .with(hash_including(report: "daily")).and_return(rows)
  end

  # A fixed lifetime window; the fold groups by weekday, not by window bounds.
  let(:window) { Pito::Analytics::Window.for("lifetime", reference_date: Date.new(2026, 6, 28)) }

  it "returns a 7-element vector indexed Monday..Sunday" do
    stub_daily({})
    result = described_class.for(groups: [], window:)
    expect(result.values.size).to eq(7)
    expect(result.values).to all(eq(0.0))
  end

  it "averages views per weekday across the calendar days of that weekday" do
    # 2026-06-01 and 2026-06-08 are both Mondays (cwday 1).
    stub_daily(
      "vid" => [
        { "day" => "2026-06-01", "views" => 10 }, # Monday
        { "day" => "2026-06-08", "views" => 30 }, # Monday
        { "day" => "2026-06-02", "views" => 50 }  # Tuesday
      ]
    )
    result = described_class.for(groups: [], window:)
    expect(result.values[0]).to eq(20.0) # Mon: (10+30)/2
    expect(result.values[1]).to eq(50.0) # Tue: 50/1
    expect(result.values[2]).to eq(0.0)  # Wed: no data
  end

  it "sums views across subjects on the same calendar day before averaging" do
    stub_daily(
      "vidA" => [ { "day" => "2026-06-01", "views" => 10 } ], # Monday
      "vidB" => [ { "day" => "2026-06-01", "views" => 15 } ]  # same Monday
    )
    result = described_class.for(groups: [], window:)
    expect(result.values[0]).to eq(25.0) # one Monday, 10+15 views
  end

  it "tolerates symbol keys and ignores unparseable days" do
    stub_daily(
      "vid" => [
        { day: Date.new(2026, 6, 3), views: 40 },      # Wednesday
        { "day" => "not-a-date", "views" => 999 }
      ]
    )
    result = described_class.for(groups: [], window:)
    expect(result.values[2]).to eq(40.0) # Wed
    expect(result.values.sum).to eq(40.0)
  end
end
