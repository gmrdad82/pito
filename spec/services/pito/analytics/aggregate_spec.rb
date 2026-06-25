# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Aggregate do
  def row(views:, mins: 0, sg: 0, sl: 0, likes: 0, dis: 0, com: 0, dur: 0, pct: 0.0)
    {
      "views" => views, "estimated_minutes_watched" => mins,
      "subscribers_gained" => sg, "subscribers_lost" => sl,
      "likes" => likes, "dislikes" => dis, "comments" => com,
      "average_view_duration" => dur, "average_view_percentage" => pct
    }
  end

  it "sums additive metrics across videos" do
    cur = {
      "a" => row(views: 100, mins: 60, sg: 5, sl: 1, likes: 10, dis: 1, com: 2),
      "b" => row(views: 50,  mins: 30, sg: 1, sl: 0, likes: 3,  dis: 0, com: 1)
    }
    res = described_class.scalars(current: cur)
    expect(res[:views][:current]).to eq(150)
    expect(res[:watched_hours][:current]).to eq(1.5) # 90 min ÷ 60
    expect(res[:subs_gained][:current]).to eq(6)
    expect(res[:subs_lost][:current]).to eq(1)
    expect(res[:likes][:current]).to eq(13)
    expect(res[:dislikes][:current]).to eq(1)
    expect(res[:comments][:current]).to eq(3)
  end

  it "views-weights the ratio metrics" do
    cur = {
      "a" => row(views: 100, dur: 60, pct: 50.0),
      "b" => row(views: 300, dur: 20, pct: 90.0)
    }
    # dur = (60*100 + 20*300)/400 = 30 ; pct = (50*100 + 90*300)/400 = 80.0
    res = described_class.scalars(current: cur)
    expect(res[:avg_view_duration][:current]).to eq(30)
    expect(res[:avg_viewed_pct][:current]).to eq(80.0)
  end

  it "carries the previous window for trends, nil when absent" do
    cur  = { "a" => row(views: 100) }
    prev = { "a" => row(views: 80) }
    expect(described_class.scalars(current: cur, previous: prev)[:views]).to eq(current: 100, previous: 80)
    expect(described_class.scalars(current: cur, previous: nil)[:views][:previous]).to be_nil
  end

  it "guards divide-by-zero when there are no views" do
    res = described_class.scalars(current: { "a" => row(views: 0, dur: 99, pct: 99.0) })
    expect(res[:avg_view_duration][:current]).to eq(0)
    expect(res[:avg_viewed_pct][:current]).to eq(0.0)
  end

  it "skips blank/nil rows" do
    res = described_class.scalars(current: { "a" => row(views: 10), "b" => nil, "c" => {} })
    expect(res[:views][:current]).to eq(10)
  end

  it "returns the canonical Scalars render-order keys" do
    expect(described_class.scalars(current: {}).keys).to eq(Pito::Analytics::Scalars::KEYS)
  end
end
