# frozen_string_literal: true

require "rails_helper"

# Pito::Analytics::Slots::Regular is the REGULAR-size metric cell wrapper for
# large visualizers (area, heart, bar). It owns the stable dom-id so broadcaster
# fragment swaps always land on the right element. Three render branches:
#   loading:  NoData(:regular) canvas + LoadingDots (no caption/visualizer slots).
#   no_data:  NoData(:regular) canvas + caption slot.
#   filled:   visualizer slot + caption slot.
RSpec.describe Pito::Analytics::Slots::Regular, type: :component do
  # ── dom-id ───────────────────────────────────────────────────────────────────

  context "with token + key" do
    subject(:node) { render_inline(described_class.new(key: :views, token: "abc")) }

    it "sets the dom-id on the cell wrapper" do
      cell = node.at_css(".pito-analytics-scalars__cell")
      expect(cell["id"]).to eq("abc__metric_views")
    end
  end

  context "without token" do
    subject(:node) { render_inline(described_class.new(key: :views)) }

    it "renders the cell wrapper without an id attribute" do
      cell = node.at_css(".pito-analytics-scalars__cell")
      expect(cell["id"]).to be_nil
    end
  end

  # ── loading state ────────────────────────────────────────────────────────────

  context "loading: true" do
    subject(:node) { render_inline(described_class.new(key: :views, loading: true)) }

    it "renders the NoData regular placeholder (.pito-metric--nodata)" do
      expect(node.at_css(".pito-metric.pito-metric--nodata")).to be_present
    end

    it "renders NoData at the full regular canvas (11 rows)" do
      expect(node.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Base::ROWS)
    end

    it "renders LoadingDots (.pito-loading-dots) where the caption goes" do
      expect(node.at_css(".pito-loading-dots")).to be_present
    end

    it "does NOT render any caption element" do
      expect(node.at_css(".pito-metric__caption")).to be_nil
    end

    it "does NOT render any visualizer slot content" do
      # loading branch bypasses the :visualizer slot entirely
      expect(node.at_css(".pito-metric--area-chart")).to be_nil
      expect(node.at_css(".pito-metric--bar")).to be_nil
      expect(node.at_css(".pito-metric--heart")).to be_nil
    end
  end

  # ── no_data state ────────────────────────────────────────────────────────────

  context "no_data: true" do
    subject(:node) do
      render_inline(described_class.new(key: :views, no_data: true)) do |c|
        c.with_caption { '<p class="pito-metric__caption">n/a</p>'.html_safe }
      end
    end

    it "renders the NoData regular placeholder" do
      expect(node.at_css(".pito-metric.pito-metric--nodata")).to be_present
    end

    it "renders NoData at the full regular canvas (11 rows)" do
      expect(node.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Base::ROWS)
    end

    it "renders the caption slot content" do
      expect(node.at_css(".pito-metric__caption").text).to eq("n/a")
    end

    it "does NOT render LoadingDots" do
      expect(node.at_css(".pito-loading-dots")).to be_nil
    end
  end

  # ── filled state ─────────────────────────────────────────────────────────────

  context "filled (visualizer + caption slots)" do
    subject(:node) do
      render_inline(described_class.new(key: :views, token: "tok")) do |c|
        c.with_visualizer { '<div class="test-viz">chart</div>'.html_safe }
        c.with_caption { '<p class="pito-metric__caption">42 views.</p>'.html_safe }
      end
    end

    it "renders the visualizer slot" do
      expect(node.at_css(".test-viz")).to be_present
      expect(node.at_css(".test-viz").text).to eq("chart")
    end

    it "renders the caption slot beneath the visualizer" do
      expect(node.at_css(".pito-metric__caption").text).to eq("42 views.")
    end

    it "does NOT render a NoData placeholder" do
      expect(node.at_css(".pito-metric--nodata")).to be_nil
    end

    it "does NOT render LoadingDots" do
      expect(node.at_css(".pito-loading-dots")).to be_nil
    end
  end
end
