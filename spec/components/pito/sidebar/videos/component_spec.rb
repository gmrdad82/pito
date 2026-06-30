# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Videos::Component do
  # Minimal stubs mimicking the public API used by the component.
  ChannelStub = Struct.new(:handle, keyword_init: true) do
    def at_handle
      "@#{handle.to_s.sub(/\A@+/, '')}"
    end
  end

  VideoStub = Struct.new(:id, :title, :channel, keyword_init: true) do
    def initialize(id:, title:, channel: nil)
      super(id:, title:, channel:)
    end
  end

  let(:channel)      { ChannelStub.new(handle: "gmrdad82") }
  let(:vid1)         { VideoStub.new(id: 1, title: "Lies of P Playthrough", channel: channel) }
  let(:vid2)         { VideoStub.new(id: 2, title: "Hollow Knight 100%",    channel: channel) }
  let(:vid_no_chan)  { VideoStub.new(id: 3, title: "Orphan Vid") }

  describe "video rows" do
    it "renders a .pito-video-row for each video" do
      node = render_inline(described_class.new(videos: [ vid1, vid2 ]))
      expect(node.css(".pito-video-row").size).to eq(2)
    end

    it "embeds the video id as data-video-id on each row" do
      node = render_inline(described_class.new(videos: [ vid1, vid2 ]))
      ids = node.css(".pito-video-row").map { |el| el["data-video-id"].to_i }
      expect(ids).to contain_exactly(1, 2)
    end

    it "renders the video title in each row" do
      node = render_inline(described_class.new(videos: [ vid1, vid2 ]))
      expect(node.to_html).to include("Lies of P Playthrough")
      expect(node.to_html).to include("Hollow Knight 100%")
    end

    it "renders the #-prefixed video id right-aligned" do
      node = render_inline(described_class.new(videos: [ vid1 ]))
      id_cell = node.css("span.tabular-nums.text-right").first
      expect(id_cell.text.strip).to eq("##{vid1.id}")
    end

    it "renders the @handle at the right of the row" do
      node = render_inline(described_class.new(videos: [ vid1 ]))
      expect(node.to_html).to include("@gmrdad82")
    end

    it "skips the @handle when the video has no channel" do
      node = render_inline(described_class.new(videos: [ vid_no_chan ]))
      expect(node.to_html).not_to include("@")
    end
  end

  describe "search input" do
    it "renders a search input with the input target" do
      node = render_inline(described_class.new(videos: [ vid1 ]))
      input = node.css("input[data-pito--videos-nav-target='input']")
      expect(input).not_to be_empty
    end

    it "renders a list container with the list target" do
      node = render_inline(described_class.new(videos: [ vid1 ]))
      list = node.css("[data-pito--videos-nav-target='list']")
      expect(list).not_to be_empty
    end

    it "renders a hidden shimmer (dots) indicator with the shimmer target" do
      node    = render_inline(described_class.new(videos: [ vid1 ]))
      shimmer = node.css("[data-pito--videos-nav-target='shimmer']")
      expect(shimmer).not_to be_empty
      expect(shimmer.first["class"]).to include("hidden")
    end
  end

  describe "controller mount point" do
    it "mounts pito--videos-nav controller on the outer div" do
      node = render_inline(described_class.new(videos: [ vid1 ]))
      expect(node.css("[data-controller='pito--videos-nav']")).not_to be_empty
    end
  end

  describe "empty state" do
    it "renders no video rows when videos is empty" do
      node = render_inline(described_class.new(videos: []))
      expect(node.css(".pito-video-row")).to be_empty
    end

    it "renders a non-empty empty-state paragraph when videos is empty" do
      node = render_inline(described_class.new(videos: []))
      expect(node.css("p").text).not_to be_empty
    end
  end

  describe "caret" do
    subject(:node) { render_inline(described_class.new(videos: [])) }

    it "uses the normal native caret on the search input (no block-caret)" do
      input = node.css("input[data-pito--videos-nav-target='input']").first
      expect(input).to be_present
      expect(input["class"]).not_to include("pito-block-caret")
    end

    it "renders no bespoke caret/trail machinery" do
      expect(node.css("[data-controller~='pito--terminal-caret']")).to be_empty
      expect(node.css("[data-controller~='pito--cursor-trail']")).to be_empty
      expect(node.css("span.terminal-caret")).to be_empty
      expect(node.css("[data-pito--terminal-caret-target]")).to be_empty
      expect(node.css(".pito-caret-input")).to be_empty
    end
  end
end
