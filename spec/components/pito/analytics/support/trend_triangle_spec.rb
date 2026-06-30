# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Support::TrendTriangle do
  def triangle(value:, previous:)
    described_class.new(value:, previous:)
  end

  describe "#trend" do
    it "is :up when the current beats the prior window" do
      expect(triangle(value: 1200, previous: 1000).trend).to eq(:up)
    end

    it "is :down when the current trails the prior window" do
      expect(triangle(value: 800, previous: 1000).trend).to eq(:down)
    end

    it "is :steady within the band of the prior window" do
      expect(triangle(value: 1010, previous: 1000).trend).to eq(:steady)
    end

    it "is :neutral when there is no prior baseline (lifetime / nil)" do
      expect(triangle(value: 500, previous: nil).trend).to eq(:neutral)
    end

    it "is :neutral when the prior window was zero (no ratio possible)" do
      expect(triangle(value: 500, previous: 0).trend).to eq(:neutral)
    end
  end

  describe "rendering" do
    it "renders ▲ green-up with a shimmer offset on a rise" do
      node = render_inline(triangle(value: 1200, previous: 1000))
      span = node.css("span.pito-metric__trend").first
      expect(span.text).to eq("▲")
      expect(span["class"]).to include("pito-trend-number--up")
      expect(span["class"]).to match(/pito-shimmer-d\d+/)
      expect(span["data-trend"]).to eq("up")
      expect(span["aria-hidden"]).to eq("true")
    end

    it "renders ▼ red-down on a fall" do
      span = render_inline(triangle(value: 800, previous: 1000)).css("span").first
      expect(span.text).to eq("▼")
      expect(span["class"]).to include("pito-trend-number--down")
    end

    it "renders – steady (fg-default shimmer, no good/bad colour)" do
      span = render_inline(triangle(value: 1010, previous: 1000)).css("span").first
      expect(span.text).to eq("–")
      expect(span["class"]).to include("pito-trend-number--steady")
    end

    it "renders NOTHING when there is no comparable baseline" do
      expect(render_inline(triangle(value: 500, previous: nil)).to_html.strip).to eq("")
    end
  end

  describe ".html (no view context)" do
    it "returns an html-safe span for a directional trend" do
      html = described_class.html(value: 1200, previous: 1000)
      expect(html).to be_html_safe
      expect(html).to include("▲")
      expect(html).to include("pito-trend-number--up")
    end

    it "returns an empty html-safe buffer when neutral" do
      html = described_class.html(value: 500, previous: nil)
      expect(html).to be_html_safe
      expect(html.to_s).to eq("")
    end
  end
end
