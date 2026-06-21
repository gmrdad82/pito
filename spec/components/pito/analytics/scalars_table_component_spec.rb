# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::ScalarsTableComponent, type: :component do
  def result(comparable: true, **overrides)
    metrics = {
      views:             { current: 1234, previous: 1000 },
      watched_hours:     { current: 12.5, previous: 10.0 },
      avg_view_duration: { current: 245,  previous: 200 },
      avg_viewed_pct:    { current: 38.2, previous: 40.0 },
      subs_gained:       { current: 20,   previous: 10 },
      subs_lost:         { current: 9,    previous: 4 },
      likes:             { current: 210,  previous: 180 },
      dislikes:          { current: 4,    previous: 2 },
      comments:          { current: 31,   previous: 30 }
    }.merge(overrides)
    Pito::Analytics::Scalars::Result.new(metrics: metrics, label: "28d", comparable: comparable)
  end

  def render_for(res)
    render_inline(described_class.new(result: res))
  end

  it "renders all nine metric labels (comments → Comms)" do
    node = render_for(result)
    text = node.text
    %w[Views Watch\ hours Avg\ view\ duration Avg\ viewed\ % Subs\ gained Subs\ lost Likes Dislikes Comms].each do |label|
      expect(text).to include(label)
    end
  end

  it "renders the value via TrendNumberComponent with the right trend" do
    node = render_for(result)
    spans = node.css("span.pito-trend-number")
    expect(spans.size).to eq(9)
    # views rose → up
    expect(node.css("span.pito-trend-number[data-trend='up']")).not_to be_empty
  end

  describe "formatting" do
    it "formats counts compactly" do
      expect(render_for(result).text).to include("1.2K") # views
    end

    it "formats avg view duration as m:ss" do
      expect(render_for(result).text).to include("4:05") # 245s
    end

    it "formats avg viewed % as a rounded percentage" do
      expect(render_for(result).text).to include("38%")
    end

    it "formats watch hours under 10 with a decimal + h suffix" do
      expect(render_for(result(watched_hours: { current: 8.5, previous: 7.0 })).text).to include("8.5h")
    end

    it "formats watch hours of 10+ compactly with an h suffix" do
      expect(render_for(result(watched_hours: { current: 12.5, previous: 10.0 })).text).to include("13h")
    end

    it "shows an em dash for a nil value" do
      node = render_for(result(views: { current: nil, previous: nil }))
      expect(node.text).to include("—")
    end
  end

  describe "polarity" do
    it "renders a numeric rise in a more-is-worse metric (subs lost) as down" do
      # subs_lost current 9 > previous 4 → numeric up, polarity false → visual down
      node = render_for(result)
      down = node.css("span.pito-trend-number[data-trend='down']").map(&:text)
      expect(down).to include(Pito::Formatter::CompactCount.call(9))
    end
  end

  describe "lifetime (no baseline)" do
    it "renders every value as neutral when not comparable" do
      node = render_for(result(comparable: false))
      expect(node.css("span.pito-trend-number[data-trend='up']")).to be_empty
      expect(node.css("span.pito-trend-number[data-trend='down']")).to be_empty
      expect(node.css("span.pito-trend-number[data-trend='neutral']").size).to eq(9)
    end
  end
end
