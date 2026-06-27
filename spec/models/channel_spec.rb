# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel, type: :model do
  describe "#at_handle" do
    it "returns the handle unchanged when it already has a leading @" do
      channel = build(:channel, handle: "@foo")
      expect(channel.at_handle).to eq("@foo")
    end

    it "adds a leading @ when the handle is stored without one" do
      channel = build(:channel, handle: "bar")
      expect(channel.at_handle).to eq("@bar")
    end

    it "never double-prefixes a handle stored as @@something" do
      channel = build(:channel, handle: "@@oops")
      expect(channel.at_handle).to eq("@oops")
    end

    it "handles nil handle gracefully" do
      channel = build(:channel, handle: nil)
      expect(channel.at_handle).to eq("@")
    end
  end

  describe "#youtube_channel_url" do
    it "returns the @handle form URL when handle is present" do
      channel = build(:channel, handle: "@gmrdad82", youtube_channel_id: "UCtest")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/@gmrdad82")
    end

    it "strips a leading @ before building the URL" do
      channel = build(:channel, handle: "gmrdad82", youtube_channel_id: "UCtest")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/@gmrdad82")
    end

    it "returns the /channel/<id> form when handle is blank" do
      channel = build(:channel, handle: nil, youtube_channel_id: "UCabc123")
      expect(channel.youtube_channel_url).to eq("https://www.youtube.com/channel/UCabc123")
    end
  end

  describe "#youtube_studio_url" do
    it "returns the Studio URL using youtube_channel_id" do
      channel = build(:channel, youtube_channel_id: "UCxyz999")
      expect(channel.youtube_studio_url).to eq("https://studio.youtube.com/channel/UCxyz999")
    end
  end
end
