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

  it "renders the @all channel label in cyan in the meta line" do
    node = render_inline(described_class.new(payload: { text: "hello" }))
    meta = node.css(".pito-echo__meta").first
    expect(meta).not_to be_nil
    expect(meta.css("span.text-cyan").text).to include("@all")
  end

  it "uses mx-2 spacing for the separator dot (spans touching, margin via CSS)" do
    node = render_inline(described_class.new(payload: { text: "hello" }))
    meta = node.css(".pito-echo__meta").first
    dot_span = meta.css("span.text-fg-faded").find { |s| s.text == "·" }
    expect(dot_span).not_to be_nil
    expect(dot_span["class"]).to include("mx-2")
  end

  it "renders a formatted timestamp when event is given" do
    event = build(:event, created_at: Time.zone.parse("2026-06-01 23:45:00"))
    node  = render_inline(described_class.new(payload: { text: "hi" }, event:))
    expect(node.css(".pito-echo__meta").first.to_html).to include("11:45 PM")
  end
end
