# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::ItemComponent do
  def build_channel(attrs = {})
    build_stubbed(:channel, {
      id:                  7,
      title:               "Test Channel",
      handle:              "@testhandle",
      youtube_channel_id:  "UCtest123"
    }.merge(attrs))
  end

  # ── Handle ───────────────────────────────────────────────────────────────────

  describe "handle" do
    it "renders the @-prefixed handle" do
      channel = build_channel(handle: "@mychannel")
      html = render_inline(described_class.new(channel: channel)).to_html
      expect(html).to include("@mychannel")
    end

    it "renders the handle inside .pito-channel-item__handle" do
      channel = build_channel(handle: "@mychannel")
      node = render_inline(described_class.new(channel: channel))
      expect(node.at_css(".pito-channel-item__handle").text.strip).to eq("@mychannel")
    end
  end

  # ── Title ────────────────────────────────────────────────────────────────────

  describe "title" do
    it "renders the channel title inside .pito-channel-item__title" do
      channel = build_channel(title: "My Awesome Channel")
      node = render_inline(described_class.new(channel: channel))
      expect(node.at_css(".pito-channel-item__title").text.strip).to eq("My Awesome Channel")
    end
  end

  # ── Channel id ───────────────────────────────────────────────────────────────

  describe "channel id" do
    it "renders the #-prefixed channel id inside .pito-channel-item__id" do
      channel = build_channel(id: 42)
      node = render_inline(described_class.new(channel: channel))
      expect(node.at_css(".pito-channel-item__id").text.strip).to eq("#42")
    end
  end

  # ── show_visit: true ─────────────────────────────────────────────────────────

  describe "show_visit: true" do
    it "renders a plain [view] link (NOT the auto-navigating VisitComponent)" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      # Must be a plain manual anchor — VisitComponent auto-clicks/navigates on render.
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
      link = node.at_css(".pito-channel-item__visit-link")
      expect(link).to be_present
      expect(link.text.strip).to eq("[view]")
    end

    it "opens the [view] link in a new tab with the YouTube URL" do
      channel = build_channel(handle: "@visitme")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      link = node.css("a[href*='youtube.com']").first
      expect(link).to be_present
      expect(link["href"]).to include("https://www.youtube.com/@visitme")
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end

    it "uses the channel_id URL when the handle is blank" do
      channel = build_channel(handle: nil, youtube_channel_id: "UCabc123")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      link = node.at_css(".pito-channel-item__visit-link")
      expect(link["href"]).to eq("https://www.youtube.com/channel/UCabc123")
    end
  end

  # ── show_visit: false (default) ──────────────────────────────────────────────

  describe "show_visit: false (default)" do
    it "does not render a VisitComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel))
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
      expect(node.css(".pito-channel-visit")).to be_empty
    end

    it "does not render any YouTube link" do
      channel = build_channel(handle: "@nope")
      node = render_inline(described_class.new(channel: channel))
      expect(node.css("a[href*='youtube.com']")).to be_empty
    end
  end

  # ── score: Integer ───────────────────────────────────────────────────────────

  describe "score: Integer" do
    it "renders a ScoreBarComponent inside .pito-channel-item__score" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, score: 75))
      expect(node.css(".pito-channel-item__score .pito-score-bar")).not_to be_empty
    end

    it "passes the score value to the ScoreBarComponent (data-score attribute)" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, score: 82))
      bar = node.at_css(".pito-score-bar[data-score]")
      expect(bar["data-score"]).to eq("82")
    end

    it "renders the bar with the correct tier for the given score" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, score: 91))
      bar = node.at_css(".pito-score-bar[data-tier='excellent']")
      expect(bar).to be_present
    end
  end

  # ── score: nil (default) ─────────────────────────────────────────────────────

  describe "score: nil (default)" do
    it "does not render a ScoreBarComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel))
      expect(node.css(".pito-channel-item__score")).to be_empty
      expect(node.css(".pito-score-bar")).to be_empty
    end
  end

  # ── Combined: show_visit: true + score present ───────────────────────────────

  describe "show_visit: true AND score present" do
    it "renders both the [view] link and the ScoreBarComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, show_visit: true, score: 70))
      expect(node.css(".pito-channel-item__score .pito-score-bar")).not_to be_empty
      expect(node.at_css(".pito-channel-item__visit-link")).to be_present
    end
  end
end
