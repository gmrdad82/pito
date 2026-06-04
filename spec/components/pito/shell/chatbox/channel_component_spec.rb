# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::ChannelComponent do
  it "does NOT render a 'Channel' muted label (removed in new design)" do
    node = render_inline(described_class.new(channel: "@all"))
    faded_texts = node.css("span.text-fg-faded").map(&:text)
    expect(faded_texts).not_to include("Channel")
  end

  it "renders the channel as a cyan @handle via ChannelHandleComponent" do
    node = render_inline(described_class.new(channel: "@all"))
    cyan = node.css("span.text-cyan").first
    expect(cyan).not_to be_nil
    expect(cyan.text).to eq("@all")
  end

  it "renders @gmrdad82 in cyan" do
    node = render_inline(described_class.new(channel: "@gmrdad82"))
    cyan = node.css("span.text-cyan").first
    expect(cyan).not_to be_nil
    expect(cyan.text).to eq("@gmrdad82")
  end

  it "renders 'none' in red when channel is 'none' (no channels connected)" do
    node = render_inline(described_class.new(channel: "none"))
    red = node.css("span.text-red").first
    expect(red).not_to be_nil
    expect(red.text).to eq("none")
    expect(node.css("span.text-cyan")).to be_empty
  end

  it "renders the shift+tab shortcut in bold yellow" do
    node = render_inline(described_class.new(channel: "@all"))
    yellow = node.css("span.font-bold.text-yellow").first
    expect(yellow).not_to be_nil
    expect(yellow.text).to include("shift+tab")
  end

  it "renders shift+tab before the channel value (shortcut is the label)" do
    node = render_inline(described_class.new(channel: "@all"))
    spans = node.css("span.inline-flex.items-center.gap-1 > span")
    first_span = spans.first
    expect(first_span["class"]).to include("font-bold")
    expect(first_span["class"]).to include("text-yellow")
    expect(first_span.text).to include("shift+tab")
  end

  it "uses tight gap-1 spacing (inline-flex wrapper)" do
    node = render_inline(described_class.new(channel: "@all"))
    wrapper = node.css("span.inline-flex.items-center.gap-1").first
    expect(wrapper).not_to be_nil
  end
end
