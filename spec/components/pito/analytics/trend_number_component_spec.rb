# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::TrendNumberComponent do
  describe "display" do
    it "formats the value with CompactCount" do
      node = render_inline(described_class.new(value: 1_234, previous: 1_000))
      expect(node.text).to eq("1.2K")
    end

    it "uses the display override when given (e.g. a duration or percentage)" do
      node = render_inline(described_class.new(value: 245, previous: 200, display: "4:05"))
      expect(node.text).to eq("4:05")
    end

    it "shows an em dash for a nil value" do
      node = render_inline(described_class.new(value: nil))
      expect(node.text).to eq("—")
    end
  end

  describe "trend direction (higher is better)" do
    it "is :up when the value rose beyond the band" do
      expect(described_class.new(value: 110, previous: 100).trend).to eq(:up)
    end

    it "is :down when the value fell beyond the band" do
      expect(described_class.new(value: 90, previous: 100).trend).to eq(:down)
    end

    it "is :steady within the band" do
      expect(described_class.new(value: 101, previous: 100).trend).to eq(:steady)
    end
  end

  describe "no baseline" do
    it "is :neutral for a lifetime window (not comparable), even with a previous" do
      expect(described_class.new(value: 500, previous: 100, comparable: false).trend).to eq(:neutral)
    end

    it "is :up for growth from a nil previous (e.g. a just-released video)" do
      expect(described_class.new(value: 5, previous: nil).trend).to eq(:up)
    end

    it "is :up for growth from a zero previous" do
      expect(described_class.new(value: 5, previous: 0).trend).to eq(:up)
    end

    it "is :neutral when there is nothing now and nothing before" do
      expect(described_class.new(value: 0, previous: nil).trend).to eq(:neutral)
    end

    it "is :neutral for a nil value" do
      expect(described_class.new(value: nil, previous: 100).trend).to eq(:neutral)
    end
  end

  describe "polarity (higher_is_better: false — dislikes, subs lost)" do
    it "shows a numeric rise as :down (bad)" do
      expect(described_class.new(value: 110, previous: 100, higher_is_better: false).trend).to eq(:down)
    end

    it "shows a numeric fall as :up (good)" do
      expect(described_class.new(value: 90, previous: 100, higher_is_better: false).trend).to eq(:up)
    end

    it "inverts growth-from-nothing to :down" do
      expect(described_class.new(value: 5, previous: nil, higher_is_better: false).trend).to eq(:down)
    end

    it "leaves :steady unchanged" do
      expect(described_class.new(value: 101, previous: 100, higher_is_better: false).trend).to eq(:steady)
    end
  end

  describe "rendering" do
    def span_for(**kwargs)
      render_inline(described_class.new(**kwargs)).css("span.pito-trend-number").first
    end

    it "adds the --up modifier + data-trend for a rising value" do
      span = span_for(value: 110, previous: 100)
      expect(span["class"]).to include("pito-trend-number--up")
      expect(span["data-trend"]).to eq("up")
    end

    it "adds the --down modifier for a falling value" do
      span = span_for(value: 90, previous: 100)
      expect(span["class"]).to include("pito-trend-number--down")
      expect(span["data-trend"]).to eq("down")
    end

    it "uses the bare class (no shimmer modifier) for steady" do
      span = span_for(value: 101, previous: 100)
      expect(span["class"]).to eq("pito-trend-number")
      expect(span["data-trend"]).to eq("steady")
    end

    it "uses the bare class for a lifetime/neutral value" do
      span = span_for(value: 500, previous: 100, comparable: false)
      expect(span["class"]).to eq("pito-trend-number")
      expect(span["data-trend"]).to eq("neutral")
    end

    it "does not render any arrow/glyph — just the number" do
      node = render_inline(described_class.new(value: 110, previous: 100))
      expect(node.text).to eq("110")
    end
  end
end
