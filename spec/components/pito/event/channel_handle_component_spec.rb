# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ChannelHandleComponent do
  it "renders @handle in cyan" do
    node = render_inline(described_class.new("all"))
    expect(node.text).to eq("@all")
    expect(node.css("span.text-cyan")).to be_present
  end

  it "renders @manfyhard in cyan" do
    node = render_inline(described_class.new("manfyhard"))
    expect(node.text).to eq("@manfyhard")
    expect(node.css("span.text-cyan")).to be_present
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
