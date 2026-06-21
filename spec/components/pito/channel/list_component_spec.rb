# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::ListComponent do
  def build_channel(attrs = {})
    build_stubbed(:channel, {
      id:                  1,
      title:               "Test Channel",
      handle:              "@testhandle",
      youtube_channel_id:  "UCtest123"
    }.merge(attrs))
  end

  describe "avatar" do
    it "renders the avatar image from our local variant when attached" do
      channel = build_channel
      allow(channel).to receive(:avatar_variant_url).and_return("/rails/active_storage/blobs/avatar.jpg")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("/rails/active_storage/blobs/avatar.jpg")
    end

    it "renders a placeholder when no avatar is attached" do
      channel = build_channel
      allow(channel).to receive(:avatar_variant_url).and_return(nil)
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("pito-channel-item__avatar--placeholder")
      expect(html).not_to include("<img")
    end
  end

  describe "title" do
    it "renders the channel title (via ItemComponent)" do
      channel = build_channel(title: "My Cool Channel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("My Cool Channel")
    end
  end

  describe "@handle and [visit] link (via ItemComponent)" do
    it "renders the @handle" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("@mychannel")
    end

    it "renders the [view] link to the youtube.com/@handle URL when handle is present" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      # ItemComponent renders a plain manual [view] anchor with the YouTube URL.
      expect(html).to include("https://www.youtube.com/@mychannel")
    end

    it "opens the visit link in a new tab (target=_blank)" do
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

  describe "channel id (via ItemComponent)" do
    it "does not render the #-prefixed channel id" do
      channel = build_channel(id: 42)
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-channel-item__id")).to be_empty
      expect(node.to_html).not_to include("#42")
    end
  end

  describe "no score bar" do
    it "does not render a ScoreBarComponent (show_visit: true, score: nil)" do
      channel = build_channel
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-score-bar")).to be_empty
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

  describe "stat counters" do
    it "renders S (subs) and V (views) counters for each channel" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(3)
      allow(channel).to receive(:view_count).and_return(7)
      node = render_inline(described_class.new(channels: [ channel ]))
      counters = node.at_css(".pito-stats-counters")
      expect(counters).to be_present
      expect(counters.text).to include("S")
      expect(counters.text).to include("V")
    end

    it "shows '1 S' for subscriber_count of 1" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(1)
      allow(channel).to receive(:view_count).and_return(0)
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("1").and include("S")
    end

    it "shows '5 V' for view_count of 5" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(0)
      allow(channel).to receive(:view_count).and_return(5)
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-stats-counters__cell").last.text.strip).to include("5").and include("V")
    end
  end

  describe "footer legend" do
    it "renders 'S subs, D vids, V views' via .pito-stats-legend" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(0)
      allow(channel).to receive(:view_count).and_return(0)
      node = render_inline(described_class.new(channels: [ channel ]))
      legend = node.at_css(".pito-stats-legend")
      expect(legend).to be_present
      expect(legend.text).to include("S").and include("subs")
      expect(legend.text).to include("D").and include("vids")
      expect(legend.text).to include("V").and include("views")
    end
  end
end
