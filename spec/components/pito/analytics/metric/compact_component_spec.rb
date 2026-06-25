# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Metric::CompactComponent, type: :component do
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

  it "renders a plain dummy 1/0 value (analyze dimension data-pulled flag)" do
    node = render_inline(described_class.new(label: "Devices", value: "1"))
    expect(node.at_css(".pito-analytics-scalars__value").text).to eq("1")
  end
end
