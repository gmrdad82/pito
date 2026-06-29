# frozen_string_literal: true

require "rails_helper"

# CompactComponent is now a THIN cell: a label/value pair, plus — when a series is
# supplied — a dedicated Metric::SparklineComponent above it (the sparkline's
# braille lives in THAT component, not inline here). Braille details are covered in
# spec/components/pito/analytics/metric/sparkline_component_spec.rb.
RSpec.describe Pito::Analytics::Metric::CompactComponent, type: :component do
  # ── No-series path (label/value only) ─────────────────────────────────────────

  it "renders the label and value in the kv-table pair markup" do
    node = render_inline(described_class.new(label: "Views", value: "1.2K"))

    pair = node.at_css(".pito-analytics-scalars__pair")
    expect(pair).to be_present
    expect(pair.at_css(".pito-analytics-scalars__label").text).to eq("Views")
    expect(pair.at_css(".pito-analytics-scalars__value").text).to eq("1.2K")
  end

  it "renders html-safe pre-rendered value content (e.g. a trend span)" do
    value = %(<span class="pito-trend-number">42</span>).html_safe
    node  = render_inline(described_class.new(label: "Comments", value: value))

    expect(node.at_css(".pito-analytics-scalars__value .pito-trend-number")).to be_present
  end

  context "without series (no chart chrome)" do
    subject(:node) { render_inline(described_class.new(label: "Likes", value: "99")) }

    it "renders only the bare pair — no sparkline, no chart wrapper, no reveal controller" do
      expect(node.at_css(".pito-analytics-scalars__pair")).to be_present
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_nil
      expect(node.at_css(".pito-metric")).to be_nil
      expect(node.css(".pito-metric__row")).to be_empty
      expect(node.to_html).not_to include("pito--area-chart-reveal")
    end
  end

  # ── Series path: delegates to the dedicated SparklineComponent ─────────────────

  context "with series present" do
    subject(:node) { render_inline(described_class.new(label: "Views", value: "1.2K", series: [ 10, 30, 20, 50 ])) }

    it "renders a dedicated SparklineComponent (.pito-metric--sparkline), not inline chart code" do
      expect(node.at_css(".pito-metric.pito-metric--sparkline")).to be_present
    end

    it "wraps the cell as charted (chart-width) with the pair spanning it" do
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_present
      expect(node.at_css(".pito-analytics-scalars__pair--charted")).to be_present
    end

    it "still renders the label/value pair" do
      pair = node.at_css(".pito-analytics-scalars__pair")
      expect(pair.at_css(".pito-analytics-scalars__label").text).to eq("Views")
      expect(pair.at_css(".pito-analytics-scalars__value").text).to eq("1.2K")
    end

    it "delegates the braille rows to the sparkline (ROWS rows present)" do
      expect(node.css(".pito-metric__row").size).to eq(Pito::Analytics::Metric::SparklineComponent::ROWS)
    end
  end

  context "with empty series (treated as no series)" do
    subject(:node) { render_inline(described_class.new(label: "Subs", value: "5", series: [])) }

    it "renders only the bare pair (no sparkline)" do
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_nil
      expect(node.at_css(".pito-analytics-scalars__pair")).to be_present
      expect(node.css(".pito-metric__row")).to be_empty
    end
  end
end
