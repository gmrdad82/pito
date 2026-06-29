# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::HandleComponent do
  it "renders #handle with the blue→purple hashtag shimmer" do
    node = render_inline(described_class.new("alpha-1322"))
    expect(node.text).to eq("#alpha-1322")
    span = node.css("span.pito-hashtag-shimmer").first
    expect(span).to be_present
    expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
  end

  it "renders data-pito-handle attribute for client handle collection" do
    node = render_inline(described_class.new("alpha-1322"))
    span = node.css("span[data-pito-handle]").first
    expect(span).to be_present
    expect(span["data-pito-handle"]).to eq("alpha-1322")
  end

  it "is DECORATIVE — the purple reply handle is NOT clickable (no prefill click)" do
    # owner 2026-06-29: only the yellow shimmer is clickable; the purple reply
    # handle no longer prefills on click (shift+r is the keybinding to reply).
    node = render_inline(described_class.new("alpha-1322"))
    span = node.css("span[data-pito-handle]").first
    expect(span["data-controller"]).to be_nil
    expect(span["data-action"]).to be_nil
    expect(span["data-pito--chat-prefill-text-value"]).to be_nil
  end

  it "renders nothing when handle is blank" do
    node = render_inline(described_class.new(""))
    expect(node.text).to be_blank
  end

  it "renders nothing when handle is nil" do
    node = render_inline(described_class.new(nil))
    expect(node.text).to be_blank
  end
end
