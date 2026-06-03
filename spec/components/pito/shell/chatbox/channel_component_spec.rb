# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::ChannelComponent do
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

  it "renders nothing when channel is blank" do
    node = render_inline(described_class.new(channel: ""))
    expect(node.text).to be_blank
  end
end
