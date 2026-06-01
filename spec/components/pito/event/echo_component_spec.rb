# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::EchoComponent do
  it "renders the echoed command text" do
    node = render_inline(described_class.new(payload: { text: "list videos" }))

    expect(node.to_html).to include("list videos")
    expect(node.css("span.text-fg").text).to include("list videos")
  end

  it "coerces a missing text payload to an empty string (no crash)" do
    node = render_inline(described_class.new(payload: {}))

    expect(node.css("span.text-fg")).not_to be_empty
    expect(node.css("span.text-fg").text.strip).to eq("")
  end

  it "wraps the echo in a Segment carrying the purple accent" do
    node = render_inline(described_class.new(payload: { text: "hello" }))

    bar = node.css(".pito-segment__bar").first
    expect(bar).not_to be_nil
    expect(bar["data-accent"]).to eq("purple")
  end

  it "renders an elevated background on the segment content" do
    node = render_inline(described_class.new(payload: { text: "hello" }))
    content = node.css(".pito-segment__content").first
    expect(content["style"]).to include("--bg-elevated")
  end

  it "renders the @all channel label in the meta line" do
    node = render_inline(described_class.new(payload: { text: "hello" }))
    expect(node.css(".pito-echo__meta").first).not_to be_nil
    expect(node.to_html).to include("@all")
  end

  it "renders a formatted timestamp when event is given" do
    event = build(:event, created_at: Time.zone.parse("2026-06-01 23:45:00"))
    node  = render_inline(described_class.new(payload: { text: "hi" }, event:))
    expect(node.css(".pito-echo__meta").first.to_html).to include("11:45 PM")
  end
end
