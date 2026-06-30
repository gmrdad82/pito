# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::ChannelDistributionComponent do
  def chan(handle:)
    Channel.new(handle: handle, youtube_channel_id: "UC#{SecureRandom.hex(4)}")
  end

  it "renders the NoData dotted canvas when shares is nil (pending)" do
    node = render_inline(described_class.new(caption: "cap"))
    expect(node.css(".pito-metric--nodata")).not_to be_empty
    expect(node.css(".pito-metric--bar")).to be_empty
  end

  it "renders the offset bar-group when shares are present" do
    shares = [
      Game::ChannelDistribution::Share.new(channel: chan(handle: "a"), share: 70, raw: {}),
      Game::ChannelDistribution::Share.new(channel: chan(handle: "b"), share: 30, raw: {})
    ]
    node = render_inline(described_class.new(caption: "cap", shares: shares))
    expect(node.css(".pito-metric--bar")).not_to be_empty
    expect(node.css(".pito-metric--nodata")).to be_empty
  end

  it "renders the caption in both states" do
    expect(render_inline(described_class.new(caption: "my cap")).text).to include("my cap")
  end
end
