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

  describe "@handle prefill token (via ItemComponent)" do
    it "renders the @handle" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channels: [ channel ])).to_html
      expect(html).to include("@mychannel")
    end

    it "wires the prefill controller to auto-run `show channel @handle`" do
      channel = build_channel(handle: "@mychannel")
      node = render_inline(described_class.new(channels: [ channel ]))
      token = node.at_css(".pito-channel-item__handle span[data-controller='pito--chat-prefill']")
      expect(token).to be_present
      expect(token["data-pito--chat-prefill-text-value"]).to eq("show channel @mychannel")
    end

    it "does not render a direct YouTube anchor on the @handle" do
      channel = build_channel(handle: "@mychannel")
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-channel-item__handle a[href*='youtube.com']")).to be_empty
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
    it "does not render a ScoreBarComponent (score: nil)" do
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
    it "renders Subs and Views word counters for each channel" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(3)
      allow(channel).to receive(:view_count).and_return(7)
      node = render_inline(described_class.new(channels: [ channel ]))
      counters = node.at_css(".pito-stats-counters")
      expect(counters).to be_present
      expect(counters.text).to include("Subs")
      expect(counters.text).to include("Views")
    end

    it "shows '1 Subs' for subscriber_count of 1" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(1)
      allow(channel).to receive(:view_count).and_return(0)
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("1").and include("Subs")
    end

    it "shows '5 Views' for view_count of 5" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(0)
      allow(channel).to receive(:view_count).and_return(5)
      allow(channel).to receive(:videos).and_return(
        double("channel_videos", count: 0)
      )
      node = render_inline(described_class.new(channels: [ channel ]))
      # Views is the last cell on row 1 (subs · views); row 2 has Vids.
      row1_cells = node.css(".pito-stats-counters")[0].css(".pito-stats-counters__cell")
      expect(row1_cells.last.text.strip).to include("5").and include("Views")
    end
  end

  describe "footer legend" do
    it "no longer renders a stats legend (removed in the metric-display overhaul)" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(0)
      allow(channel).to receive(:view_count).and_return(0)
      node = render_inline(described_class.new(channels: [ channel ]))
      expect(node.css(".pito-stats-legend")).to be_empty
      expect(node.css(".pito-channel-list__legend")).to be_empty
    end
  end
end
