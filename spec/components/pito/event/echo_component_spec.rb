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

  it "does not render a channel label" do
    node = render_inline(described_class.new(payload: { text: "hello" }))
    expect(node.css("span.text-cyan")).to be_empty
  end

  it "renders the timestamp inline (24-hour) on the first line when event is given" do
    event = build(:event, created_at: Time.zone.parse("2026-06-01 23:45:00"))
    node  = render_inline(described_class.new(payload: { text: "hi" }, event:))
    expect(node.css("span.pito-timestamp-prefix").text).to include("23:45")
  end

  # The echoed input renders INSTANTLY (item 18 removed the typewriter).
  it "renders the echo text instantly with no typewriter wiring" do
    node = render_inline(described_class.new(payload: { text: "list videos" }))
    expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    expect(node.css("[data-pito--typewriter-target]")).to be_empty
    expect(node.text).to include("list videos")
  end
end
