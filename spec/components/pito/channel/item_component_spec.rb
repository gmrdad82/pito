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

    it "wraps the @handle in a pito-token-shimmer span" do
      channel = build_channel(handle: "@mychannel")
      node    = render_inline(described_class.new(channel: channel))
      shimmer = node.css(".pito-channel-item__handle span.pito-token-shimmer").first
      expect(shimmer).to be_present
      expect(shimmer.text).to eq("@mychannel")
    end

    it "wires the prefill controller to auto-run `show channel @handle`" do
      channel = build_channel(handle: "@mychannel")
      node    = render_inline(described_class.new(channel: channel))
      token   = node.at_css(".pito-channel-item__handle span[data-controller='pito--chat-prefill']")
      expect(token).to be_present
      expect(token["data-pito--chat-prefill-text-value"]).to eq("show channel @mychannel")
    end

    it "sets the submit data attribute so the click auto-submits" do
      channel = build_channel(handle: "@mychannel")
      node    = render_inline(described_class.new(channel: channel))
      token   = node.at_css(".pito-channel-item__handle span[data-controller='pito--chat-prefill']")
      expect(token["data-pito--chat-prefill-submit-value"]).to eq("true")
    end

    it "does not render any YouTube anchor link on the handle" do
      channel = build_channel(handle: "@mychannel")
      node    = render_inline(described_class.new(channel: channel))
      expect(node.css("a[href*='youtube.com']")).to be_empty
    end

    it "does not render a VisitComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel))
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
      expect(node.css(".pito-channel-visit")).to be_empty
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
    it "does not render the #-prefixed channel id" do
      channel = build_channel(id: 42)
      node = render_inline(described_class.new(channel: channel))
      expect(node.css(".pito-channel-item__id")).to be_empty
      expect(node.to_html).not_to include("#42")
    end
  end

  # ── show_avatar ──────────────────────────────────────────────────────────────

  describe "show_avatar:" do
    it "renders the avatar image when show_avatar: true and one is attached" do
      channel = build_channel
      allow(channel).to receive(:avatar_variant_url).and_return("/rails/active_storage/blobs/avatar.jpg")
      node = render_inline(described_class.new(channel: channel, show_avatar: true))
      img = node.at_css("img.pito-channel-item__avatar")
      expect(img).to be_present
      expect(img["src"]).to include("/rails/active_storage/blobs/avatar.jpg")
    end

    it "renders the placeholder when show_avatar: true and none is attached" do
      channel = build_channel
      allow(channel).to receive(:avatar_variant_url).and_return(nil)
      node = render_inline(described_class.new(channel: channel, show_avatar: true))
      expect(node.at_css(".pito-channel-item__avatar--placeholder")).to be_present
      expect(node.css("img")).to be_empty
    end

    it "renders no avatar by default (show_avatar: false)" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel))
      expect(node.css(".pito-channel-item__avatar")).to be_empty
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

  # ── Combined: score present ───────────────────────────────────────────────────

  describe "score present" do
    it "renders both the prefill @handle token and the ScoreBarComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, score: 70))
      expect(node.css(".pito-channel-item__score .pito-score-bar")).not_to be_empty
      expect(node.at_css(".pito-channel-item__handle span[data-controller='pito--chat-prefill']")).to be_present
    end
  end

  # ── show_stats: true ─────────────────────────────────────────────────────────

  describe "show_stats: true" do
    def channel_with_stats(subscriber_count:, view_count:)
      ch = build_channel
      allow(ch).to receive(:subscriber_count).and_return(subscriber_count)
      allow(ch).to receive(:view_count).and_return(view_count)
      ch
    end

    it "renders a .pito-channel-item__stats wrapper" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.at_css(".pito-channel-item__stats")).to be_present
    end

    it "renders two counter cells (subs + views) on row 1" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").size).to eq(2)
    end

    it "renders two .pito-stats-counters rows when show_video_count: true" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      allow(channel).to receive(:videos).and_return(
        double("channel_videos", count: 3)
      )
      node = render_inline(described_class.new(channel: channel, show_stats: true, show_video_count: true))
      expect(node.css(".pito-stats-counters").size).to eq(2)
    end

    it "row 1 contains Subs · Views, row 2 contains Vids when show_video_count: true" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      allow(channel).to receive(:videos).and_return(
        double("channel_videos", count: 7)
      )
      node = render_inline(described_class.new(channel: channel, show_stats: true, show_video_count: true))
      rows = node.css(".pito-stats-counters")
      expect(rows[0].text).to include("Subs").and include("Views")
      expect(rows[1].text).to include("Vids")
    end

    it "row 1 has a · separator between Subs and Views" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.at_css(".pito-stats-counters").text).to include("·")
    end

    it "renders Subs and Views word counters" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      counters = node.at_css(".pito-stats-counters")
      expect(counters).to be_present
      expect(counters.text).to include("Subs")
      expect(counters.text).to include("Views")
    end

    it "shows '1 Subs' when subscriber_count is 1" do
      channel = channel_with_stats(subscriber_count: 1, view_count: 0)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("1").and include("Subs")
    end

    it "shows '2 Subs' when subscriber_count is 2" do
      channel = channel_with_stats(subscriber_count: 2, view_count: 0)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("2").and include("Subs")
    end

    it "shows '10 Subs' when subscriber_count is 10" do
      channel = channel_with_stats(subscriber_count: 10, view_count: 0)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("10").and include("Subs")
    end

    it "shows '1 Views' when view_count is 1" do
      channel = channel_with_stats(subscriber_count: 0, view_count: 1)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").last.text.strip).to include("1").and include("Views")
    end

    it "shows 'N Views' when view_count is N != 1" do
      channel = channel_with_stats(subscriber_count: 0, view_count: 42)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").last.text.strip).to include("42").and include("Views")
    end

    it "shows '0 Subs' when subscriber_count is nil" do
      channel = channel_with_stats(subscriber_count: nil, view_count: 5)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").first.text.strip).to include("0").and include("Subs")
    end

    it "shows '0 Views' when view_count is nil" do
      channel = channel_with_stats(subscriber_count: 5, view_count: nil)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      # last cell of row 1 is Views
      row1_cells = node.css(".pito-stats-counters")[0].css(".pito-stats-counters__cell")
      expect(row1_cells.last.text.strip).to include("0").and include("Views")
    end
  end

  # ── show_stats: false (default) ──────────────────────────────────────────────

  describe "show_stats: false (default)" do
    it "does not render any stat rows" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel))
      expect(node.css(".pito-channel-item__stats")).to be_empty
      expect(node.css(".pito-channel-item__stat")).to be_empty
    end

    it "does not render stat rows when show_stats is explicitly false" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, show_stats: false))
      expect(node.css(".pito-channel-item__stats")).to be_empty
    end
  end

  # ── show_video_count: true ───────────────────────────────────────────────────

  describe "show_video_count: true" do
    def channel_with_videos(count)
      ch = build_channel
      allow(ch).to receive(:subscriber_count).and_return(0)
      allow(ch).to receive(:view_count).and_return(0)
      allow(ch).to receive(:videos).and_return(double("channel_videos", count: count))
      ch
    end

    def render_with_video_count(channel)
      render_inline(described_class.new(channel: channel, show_stats: true, show_video_count: true))
    end

    it "renders a Vids counter cell" do
      node = render_with_video_count(channel_with_videos(3))
      cells = node.css(".pito-stats-counters__cell")
      expect(cells.any? { |c| c.text.include?("Vids") }).to be true
    end

    it "shows '1 Vids' when the channel has 1 video" do
      node = render_with_video_count(channel_with_videos(1))
      cells = node.css(".pito-stats-counters__cell")
      vids_cell = cells.find { |c| c.text.include?("Vids") }
      expect(vids_cell.text.strip).to include("1").and include("Vids")
    end

    it "shows '0 Vids' when the channel has no videos" do
      node = render_with_video_count(channel_with_videos(0))
      cells = node.css(".pito-stats-counters__cell")
      vids_cell = cells.find { |c| c.text.include?("Vids") }
      expect(vids_cell.text.strip).to include("0").and include("Vids")
    end

    it "shows 'N Vids' when the channel has N != 1 videos" do
      node = render_with_video_count(channel_with_videos(12))
      cells = node.css(".pito-stats-counters__cell")
      vids_cell = cells.find { |c| c.text.include?("Vids") }
      expect(vids_cell.text.strip).to include("12").and include("Vids")
    end

    it "places Subs and Views on row 1, Vids on row 2" do
      node = render_with_video_count(channel_with_videos(3))
      rows = node.css(".pito-stats-counters")
      expect(rows[0].text).to include("Subs").and include("Views")
      expect(rows[1].text).to include("Vids")
      expect(rows[1].text).not_to include("Subs")
      expect(rows[1].text).not_to include("Views")
    end
  end

  # ── show_video_count: false (default) ────────────────────────────────────────

  describe "show_video_count: false (default)" do
    it "does not render a Vids counter cell even when show_stats: true" do
      channel = build_channel
      allow(channel).to receive(:subscriber_count).and_return(5)
      allow(channel).to receive(:view_count).and_return(100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      cells = node.css(".pito-stats-counters__cell")
      expect(cells.none? { |c| c.text.include?("Vids") }).to be true
      expect(cells.size).to eq(2)
    end
  end
end
