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
    expect(cyan.text).to eq("@gmrdad82")
  end

  it "renders nothing when channel is blank" do
    node = render_inline(described_class.new(channel: ""))
    expect(node.text).to be_blank
  end
end
