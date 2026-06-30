# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::MetricCellComponent, type: :component do
  it "carries the <token>__metric_<key> swap-target id when a token is given" do
    node = render_inline(described_class.new(key: :views, label: "Views", token: "abcd1234", loading: true))
    expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to eq("abcd1234__metric_views")
  end

  it "omits the id when no token is given" do
    node = render_inline(described_class.new(key: :views, label: "Views", loading: true))
    expect(node.at_css(".pito-analytics-scalars__cell")["id"]).to be_nil
  end

  it "renders the loading skeleton (LoadingDots) when loading" do
    node = render_inline(described_class.new(key: :views, label: "Views", token: "t", loading: true))
    expect(node.at_css(".pito-loading-dots")).to be_present
  end

  it "renders the metric name and scalar value when filled" do
    node = render_inline(described_class.new(key: :views, label: "Views", token: "t", series: [ 1, 2, 3 ], value: "1.2K"))
    expect(node.text).to include("Views").and include("1.2K")
  end

  it "renders a sparkline when a series is supplied" do
    node = render_inline(described_class.new(key: :views, label: "Views", series: [ 1, 2, 3 ], value: "3"))
    expect(node.at_css(".pito-metric__row")).to be_present
  end

  it "renders the NoData canvas + n/a (no spinner) in the no_data state" do
    node = render_inline(described_class.new(key: :views, label: "Views", token: "t", no_data: true))
    expect(node.at_css(".pito-metric--nodata")).to be_present
    expect(node.text).to include("n/a")
    expect(node.at_css(".pito-loading-dots")).to be_nil
  end
end
