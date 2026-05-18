require "rails_helper"

# Phase 20 — friendly URLs. Channel-specific friendly_id behaviour.
#
# Channel does not include `extend FriendlyId`; lookup runs through a
# custom `Channel.friendly` finder rooted in the `channel_url` column.
# This spec exercises that contract end-to-end.
RSpec.describe Channel, type: :model do
  describe "#url_slug" do
    it "extracts the UC-id from a canonical channel URL" do
      channel = build_stubbed(:channel, channel_url: "https://www.youtube.com/channel/UCAAAAAAAAAAAAAAAAAAAAAA")
      expect(channel.url_slug).to eq("UCAAAAAAAAAAAAAAAAAAAAAA")
    end

    it "falls back to channel-<id> when no UC-id is present" do
      channel = Channel.new(channel_url: nil)
      channel.id = 17
      expect(channel.url_slug).to eq("channel-17")
    end
  end

  describe "#to_param" do
    it "returns the URL slug" do
      channel = build_stubbed(:channel)
      expect(channel.to_param).to eq(channel.url_slug)
      expect(channel.to_param).not_to eq(channel.id.to_s)
    end
  end

  describe "Channel.friendly.find" do
    let!(:channel) do
      create(:channel,
             channel_url: "https://www.youtube.com/channel/UCBBBBBBBBBBBBBBBBBBBBBB")
    end

    it "resolves by slug (UC-id)" do
      expect(Channel.friendly.find("UCBBBBBBBBBBBBBBBBBBBBBB")).to eq(channel)
    end

    it "resolves by integer id" do
      expect(Channel.friendly.find(channel.id)).to eq(channel)
    end

    it "resolves by stringified integer id" do
      expect(Channel.friendly.find(channel.id.to_s)).to eq(channel)
    end

    it "resolves by channel-<id> fallback slug" do
      expect(Channel.friendly.find("channel-#{channel.id}")).to eq(channel)
    end

    it "raises RecordNotFound on a miss" do
      expect { Channel.friendly.find("UCDoesNotExistNowhereXY") }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "uniqueness on channel_url" do
    it "rejects two channels with the same channel_url" do
      url = "https://www.youtube.com/channel/UCCCCCCCCCCCCCCCCCCCCCCC"
      create(:channel, channel_url: url)
      duplicate = build(:channel, channel_url: url)
      expect(duplicate).not_to be_valid
    end
  end
end
