# frozen_string_literal: true

require "rails_helper"

# AnalyzeCellComponent renders ONE analyze metric cell as a Slots::Regular wrapper
# (the `<token>__metric_<key>` swap target). Four render branches, mirroring the
# at-a-glance MetricCellComponent pattern:
#
#   loading → NoData(:regular) canvas + LoadingDots (no caption/visualizer)
#   no_data → NoData(:regular) canvas + caption slot (terminal, no spinner)
#   filled  → the right visualizer (heart / area / bar) + caption beneath
#   scalar  → caption only (value + label; no bespoke visualizer)
#
# The dom-id `<token>__metric_<key>` lives on the Slots::Regular wrapper so the
# per-metric broadcaster swap always lands on the right element.
RSpec.describe Pito::Analytics::AnalyzeCellComponent, type: :component do
  # ── Loading state ─────────────────────────────────────────────────────────────

  context "loading: true" do
    subject(:node) { render_inline(described_class.new(key: :views, token: "abc1234", loading: true)) }

    it "renders the NoData regular placeholder (.pito-metric--nodata)" do
      expect(node.at_css(".pito-metric.pito-metric--nodata")).to be_present
    end

    it "renders LoadingDots (.pito-loading-dots) where the caption goes" do
      expect(node.at_css(".pito-loading-dots")).to be_present
    end

    it "does NOT render a caption element" do
      expect(node.at_css(".pito-metric__caption")).to be_nil
    end

    it "sets the swap-target dom-id on the cell wrapper" do
      expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to eq("abc1234__metric_views")
    end

    context "without token" do
      subject(:node) { render_inline(described_class.new(key: :views, loading: true)) }

      it "omits the id attribute" do
        expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to be_nil
      end
    end
  end

  # ── no_data state ─────────────────────────────────────────────────────────────

  context "no_data cell" do
    let(:cell) { { no_data: true, caption: "Views" } }

    subject(:node) { render_inline(described_class.new(key: :views, token: "tok1", cell:)) }

    it "renders the NoData regular placeholder" do
      expect(node.at_css(".pito-metric.pito-metric--nodata")).to be_present
    end

    it "renders the caption text" do
      expect(node.at_css(".pito-metric__caption").text).to eq("Views")
    end

    it "does NOT render LoadingDots" do
      expect(node.at_css(".pito-loading-dots")).to be_nil
    end

    it "carries the swap-target dom-id" do
      expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to eq("tok1__metric_views")
    end
  end

  # ── Heart visualizer ──────────────────────────────────────────────────────────

  context "heart cell" do
    let(:hearts) { [ { score: 92.2, color: :red, likes: 922, dislikes: 78 } ] }
    let(:cell)   { { heart: hearts, caption: "92.20% lifetime" } }

    subject(:node) { render_inline(described_class.new(key: :likes, token: "tok2", cell:)) }

    it "renders the Heart visualizer (.pito-metric--heart)" do
      expect(node.at_css(".pito-metric--heart")).to be_present
    end

    it "renders the caption beneath the visualizer" do
      expect(node.at_css(".pito-metric__caption")).to be_present
    end

    it "does NOT render the NoData placeholder" do
      expect(node.at_css(".pito-metric--nodata")).to be_nil
    end
  end

  # ── Area (chart) visualizer ───────────────────────────────────────────────────

  context "chart cell" do
    let(:cell) do
      {
        chart:           :views,
        series:          [ 1, 2, 3 ],
        target_daily:    100.0,
        caption:         "3 Views",
        trend:           true,
        reference_token: nil,
        dates:           []
      }
    end

    subject(:node) { render_inline(described_class.new(key: :views, token: "tok3", cell:)) }

    it "renders the Area visualizer (.pito-metric--area-chart)" do
      expect(node.at_css(".pito-metric--area-chart")).to be_present
    end

    it "renders the caption beneath the visualizer" do
      expect(node.at_css(".pito-metric__caption")).to be_present
    end

    it "does NOT render the NoData placeholder" do
      expect(node.at_css(".pito-metric--nodata")).to be_nil
    end
  end

  # ── Bar visualizer ────────────────────────────────────────────────────────────

  context "bars cell" do
    let(:cell) do
      {
        bars:    [ { label: "Mobile", color: :blue, pct: 70.0, value_label: "70.0%" } ],
        caption: "Devices"
      }
    end

    subject(:node) { render_inline(described_class.new(key: :devices, token: "tok4", cell:)) }

    it "renders the Bar visualizer (.pito-metric--bar)" do
      expect(node.at_css(".pito-metric--bar")).to be_present
    end

    it "renders the caption beneath the visualizer" do
      expect(node.at_css(".pito-metric__caption")).to be_present
    end

    it "does NOT render the NoData placeholder" do
      expect(node.at_css(".pito-metric--nodata")).to be_nil
    end
  end

  # ── Scalar (caption-only) ─────────────────────────────────────────────────────

  context "scalar cell" do
    let(:cell) { { label: "Comments", value: "42" } }

    subject(:node) { render_inline(described_class.new(key: :comments, token: "tok5", cell:)) }

    it "renders the value and label in the caption" do
      text = node.at_css(".pito-metric__caption").text
      expect(text).to include("42").and include("Comments")
    end

    it "does NOT render a NoData placeholder" do
      expect(node.at_css(".pito-metric--nodata")).to be_nil
    end

    it "does NOT render any bespoke visualizer" do
      expect(node.at_css(".pito-metric--area-chart")).to be_nil
      expect(node.at_css(".pito-metric--heart")).to be_nil
      expect(node.at_css(".pito-metric--bar")).to be_nil
    end
  end

  # ── dom-id ────────────────────────────────────────────────────────────────────

  it "carries the <token>__metric_<key> id when a token is given" do
    node = render_inline(described_class.new(key: :views, token: "abcd1234", loading: true))
    expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to eq("abcd1234__metric_views")
  end

  it "omits the id when no token is given" do
    node = render_inline(described_class.new(key: :views, loading: true))
    expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to be_nil
  end

  it "converts a string key to a string in the dom-id" do
    node = render_inline(described_class.new(key: "watched_hours", token: "xyz", loading: true))
    expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to eq("xyz__metric_watched_hours")
  end
end
