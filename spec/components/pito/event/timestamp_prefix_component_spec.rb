# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::TimestampPrefixComponent do
  it "renders the time in 24-hour HH:MM (dim) followed by a · separator" do
    ts = Time.zone.parse("2026-06-01 19:58:00")
    node = render_inline(described_class.new(timestamp: ts))
    expect(node.css("span.pito-timestamp-prefix")).not_to be_empty
    expect(node.text).to include("19:58")
    expect(node.to_html).to include("·")
  end

  it "zero-pads single-digit hours and drops AM/PM (09:05)" do
    ts = Time.zone.parse("2026-06-01 09:05:00")
    html = render_inline(described_class.new(timestamp: ts)).to_html
    expect(html).to include("09:05")
    expect(html).not_to include("AM")
    expect(html).not_to include("PM")
  end

  it "renders nothing when timestamp is nil" do
    node = render_inline(described_class.new(timestamp: nil))
    expect(node.to_html.strip).to eq("")
  end
end
