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

  # The user's own echoed input types in via the typewriter (body target). It is
  # rendered instant ONLY under the JS skip guards (initial render / reduced-
  # motion / fx off) — those guards live in the controller, not the markup.
  it "mounts the typewriter controller so the echo types in" do
    node = render_inline(described_class.new(payload: { text: "list videos" }))
    expect(node.css("div[data-controller~='pito--typewriter']").first).not_to be_nil
  end

  it "tags the echo text span as the typewriter body target" do
    node = render_inline(described_class.new(payload: { text: "list videos" }))
    span = node.css("[data-controller~='pito--typewriter'] span[data-pito--typewriter-target='body']").first
    expect(span).not_to be_nil
    expect(span.text).to include("list videos")
  end

  it "sets the typewriter doneEvent to pito:echo-typed (so the comet clears)" do
    node    = render_inline(described_class.new(payload: { text: "hi" }))
    wrapper = node.css("div[data-controller~='pito--typewriter']").first
    expect(wrapper["data-pito--typewriter-done-event-value"]).to eq("pito:echo-typed")
  end
end
