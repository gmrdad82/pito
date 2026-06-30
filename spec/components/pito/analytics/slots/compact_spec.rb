# frozen_string_literal: true

require "rails_helper"

# Pito::Analytics::Slots::Compact is a modular cell: it composes
#   Support::MetricName (label) + a :scalar content slot (value) +
#   optionally a Visualizers::Sparkline or Visualizers::NoData above the pair.
# Braille detail of individual visualizers lives in their own specs.
RSpec.describe Pito::Analytics::Slots::Compact, type: :component do
  # ── filled + no series (bare pair, no canvas chrome) ─────────────────────────

  context "filled, without series" do
    subject(:node) do
      render_inline(described_class.new(name: "Likes")) { |c| c.with_scalar { "99" } }
    end

    it "renders only the bare pair — no sparkline, no chart wrapper" do
      expect(node.at_css(".pito-analytics-scalars__pair")).to be_present
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_nil
      expect(node.at_css(".pito-metric")).to be_nil
      expect(node.css(".pito-metric__row")).to be_empty
    end

    it "renders the scalar slot content in the value span" do
      expect(node.at_css(".pito-analytics-scalars__value").text.strip).to eq("99")
    end
  end

  # ── filled + series (Sparkline above the pair) ───────────────────────────────

  context "filled, with series present" do
    subject(:node) do
      render_inline(described_class.new(name: "Views", series: [ 10, 30, 20, 50 ])) { |c| c.with_scalar { "1,234" } }
    end

    it "renders a dedicated Visualizers::Sparkline (.pito-metric--sparkline)" do
      expect(node.at_css(".pito-metric.pito-metric--sparkline")).to be_present
    end

    it "wraps the cell as charted with the --charted pair modifier" do
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_present
      expect(node.at_css(".pito-analytics-scalars__pair--charted")).to be_present
    end

    it "renders the scalar slot content (no LoadingDots)" do
      expect(node.at_css(".pito-analytics-scalars__value").text.strip).to eq("1,234")
      expect(node.at_css(".pito-loading-dots")).to be_nil
    end

    it "delegates braille rows to the sparkline" do
      expect(node.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Sparkline::ROWS)
    end
  end

  context "filled, with empty series (treated as no series)" do
    subject(:node) do
      render_inline(described_class.new(name: "Subs", series: [])) { |c| c.with_scalar { "5" } }
    end

    it "renders only the bare pair (no sparkline)" do
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_nil
      expect(node.at_css(".pito-analytics-scalars__pair")).to be_present
      expect(node.css(".pito-metric__row")).to be_empty
    end
  end

  # ── loading state ────────────────────────────────────────────────────────────

  context "loading: true" do
    subject(:node) { render_inline(described_class.new(name: "Comments", loading: true)) }

    it "renders the NoData compact placeholder (.pito-metric--nodata) above the pair" do
      expect(node.at_css(".pito-metric.pito-metric--nodata")).to be_present
      expect(node.at_css(".pito-analytics-scalars__charted")).to be_present
      expect(node.css(".pito-metric__row").size).to eq(Pito::Analytics::Visualizers::Sparkline::ROWS)
    end

    it "renders LoadingDots in the value span (not the scalar slot)" do
      expect(node.at_css(".pito-analytics-scalars__value .pito-loading-dots")).to be_present
    end

    it "does NOT render any scalar slot content" do
      # No block was given — scalar slot is empty; only loading dots appear.
      value_text = node.at_css(".pito-analytics-scalars__value").inner_html
      expect(value_text).not_to include("pito-metric--sparkline")
    end
  end

  # ── name comes from Support::MetricName (.pito-analytics-scalars__label) ────

  it "uses Support::MetricName for the label in all branches" do
    node = render_inline(described_class.new(name: "Views")) { |c| c.with_scalar { "0" } }
    expect(node.at_css(".pito-analytics-scalars__label").text.strip).to eq("Views")
  end
end
