# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::ListComponent do
  def build_channel(attrs = {})
    build_stubbed(:channel, {
      id:                  1,
      title:               "Test Channel",
      handle:              "@testhandle",
      youtube_channel_id:  "UCtest123",
      avatar_url:          "https://example.com/avatar.jpg"
    }.merge(attrs))
  end

  describe "avatar" do
    it "renders the avatar image when avatar_url is present" do
      channel = build_channel(avatar_url: "https://example.com/avatar.jpg")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("https://example.com/avatar.jpg")
    end

    it "renders a placeholder when avatar_url is blank" do
      channel = build_channel(avatar_url: nil)
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("pito-channel-list__avatar--placeholder")
      expect(html).not_to include("<img")
    end
  end

  describe "title" do
    it "renders the channel title" do
      channel = build_channel(title: "My Cool Channel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("My Cool Channel")
    end
  end

  describe "@handle and [view] link" do
    it "renders the @handle" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("@mychannel")
    end

    it "renders a [view] link to the youtube.com/@handle URL when handle is present" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("https://www.youtube.com/@mychannel")
      expect(html).to include("[view]")
    end

    it "opens the link in a new tab (target=_blank)" do
      channel = build_channel(handle: "@mychannel")
      node = render_inline(described_class.new(channels: [ channel ]))
      link = node.css("a[href*='youtube.com']").first
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end

    it "uses the channel_id URL when handle is blank" do
      channel = build_channel(handle: nil, youtube_channel_id: "UCabc123")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("https://www.youtube.com/channel/UCabc123")
    end
  end

  describe "channel id" do
    it "renders the #-prefixed channel id" do
      channel = build_channel(id: 42)
      node = render_inline(described_class.new(channels: [ channel ]))
      id_element = node.css(".pito-channel-list__id").first
      expect(id_element.text.strip).to eq("#42")
    end
  end

  describe "multiple channels" do
    it "renders a card for each channel" do
      channels = [
        build_channel(id: 1, title: "Alpha", handle: "@alpha"),
        build_channel(id: 2, title: "Beta",  handle: "@beta")
      ]
      node = render_inline(described_class.new(channels:))
      expect(node.css(".pito-channel-list__card").size).to eq(2)
    end
  end
end
