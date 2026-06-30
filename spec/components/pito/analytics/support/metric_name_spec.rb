# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Support::MetricName, type: :component do
  it "renders the metric name in the label span" do
    node = render_inline(described_class.new(name: "Views"))
    label = node.css(".pito-analytics-scalars__label").first
    expect(label).to be_present
    expect(label.text).to eq("Views")
  end
end
