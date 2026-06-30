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

  describe "#banner" do
    let(:channel) { create(:channel) }
    # Raw bytes — not a processed image; the master stores whatever the CDN returned.
    let(:raw_bytes) { "fake-banner-raw-master" }

    it "is an ActiveStorage attachment, unattached by default" do
      expect(channel.banner).not_to be_attached
    end

    it "declares a :display named variant (450×253)" do
      reflection = Channel.attachment_reflections["banner"]
      expect(reflection.named_variants).to have_key(:display)
    end

    it "#banner_url is nil when no banner is attached" do
      expect(channel.banner_url).to be_nil
    end

    it "#banner_url returns a host-less proxy path once a banner is attached" do
      channel.banner.attach(io: StringIO.new(raw_bytes), filename: "banner-#{channel.id}.jpg", content_type: "image/jpeg")
      url = channel.banner_url
      expect(url).to be_present
      expect(url).to start_with("/") # host-less (loads from whatever host serves the page)
    end
  end

  describe "#avatar" do
    let(:channel)   { create(:channel) }
    let(:raw_bytes) { "fake-avatar-raw-master" }

    def attach_avatar
      channel.avatar.attach(io: StringIO.new(raw_bytes), filename: "avatar-#{channel.id}.jpg", content_type: "image/jpeg")
    end

    it "declares :lg (120×120) and :sm (60×60) named variants" do
      reflection = Channel.attachment_reflections["avatar"]
      expect(reflection.named_variants).to have_key(:lg)
      expect(reflection.named_variants).to have_key(:sm)
    end

    it "#avatar_variant_url is nil when no avatar is attached" do
      expect(channel.avatar_variant_url).to be_nil
    end

    it "#avatar_variant_url returns a host-less proxy path once an avatar is attached" do
      attach_avatar
      url = channel.avatar_variant_url
      expect(url).to be_present
      expect(url).to start_with("/")
    end

    it "#avatar_inline_url is nil when no avatar is attached" do
      expect(channel.avatar_inline_url).to be_nil
    end

    it "#avatar_inline_url returns a host-less proxy path once an avatar is attached" do
      attach_avatar
      url = channel.avatar_inline_url
      expect(url).to be_present
      expect(url).to start_with("/")
    end
  end
end
