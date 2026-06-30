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
    let(:jpeg) { Vips::Image.black(374, 210).cast(:uchar).bandjoin([ 0, 0 ]).jpegsave_buffer }

    it "is an ActiveStorage attachment, unattached by default" do
      expect(channel.banner).not_to be_attached
    end

    it "#banner_variant_url is nil when no banner is attached" do
      expect(channel.banner_variant_url).to be_nil
    end

    it "#banner_variant_url returns a host-less proxy path once a banner is attached" do
      channel.banner.attach(io: StringIO.new(jpeg), filename: "banner-#{channel.id}.jpg", content_type: "image/jpeg")
      url = channel.banner_variant_url
      expect(url).to be_present
      expect(url).to start_with("/") # host-less (loads from whatever host serves the page)
    end
  end
end
