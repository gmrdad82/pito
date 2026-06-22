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

    it "wraps the @handle in a pito-token-shimmer span (show_visit: false)" do
      channel = build_channel(handle: "@mychannel")
      node    = render_inline(described_class.new(channel: channel))
      shimmer = node.css(".pito-channel-item__handle span.pito-token-shimmer").first
      expect(shimmer).to be_present
      expect(shimmer.text).to eq("@mychannel")
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

  # ── show_visit: true ─────────────────────────────────────────────────────────

  describe "show_visit: true" do
    it "renders the @handle as a YouTube link (NOT the auto-navigating VisitComponent)" do
      channel = build_channel(handle: "@visitme")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      # Must be a plain manual anchor — VisitComponent auto-clicks/navigates on render.
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
      link = node.at_css("a.pito-channel-item__handle--link")
      expect(link).to be_present
      expect(link.text.strip).to eq(channel.at_handle)
    end

    it "wraps the linked @handle in the cyan token shimmer (handles shimmer everywhere)" do
      channel = build_channel(handle: "@visitme")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      shimmer = node.css("a.pito-channel-item__handle--link span.pito-token-shimmer").first
      expect(shimmer).to be_present
      expect(shimmer.text).to eq("@visitme")
    end

    it "no longer renders a separate [view] link" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      expect(node.css(".pito-channel-item__visit-link")).to be_empty
      expect(node.text).not_to include("[view]")
    end

    it "opens the linked handle in a new tab with the YouTube URL" do
      channel = build_channel(handle: "@visitme")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      link = node.at_css("a.pito-channel-item__handle--link")
      expect(link).to be_present
      expect(link["href"]).to include("https://www.youtube.com/@visitme")
      expect(link["target"]).to eq("_blank")
      expect(link["rel"]).to include("noopener")
    end

    it "uses the channel_id URL when the handle is blank" do
      channel = build_channel(handle: nil, youtube_channel_id: "UCabc123")
      node = render_inline(described_class.new(channel: channel, show_visit: true))
      link = node.at_css("a.pito-channel-item__handle--link")
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
    it "renders both the linked @handle and the ScoreBarComponent" do
      channel = build_channel
      node = render_inline(described_class.new(channel: channel, show_visit: true, score: 70))
      expect(node.css(".pito-channel-item__score .pito-score-bar")).not_to be_empty
      expect(node.at_css("a.pito-channel-item__handle--link")).to be_present
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

    it "renders two counter cells" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true))
      expect(node.css(".pito-stats-counters__cell").size).to eq(2)
    end

    it "joins the stats inline with · separators" do
      channel = channel_with_stats(subscriber_count: 5, view_count: 100)
      node = render_inline(described_class.new(channel: channel, show_stats: true, show_video_count: true))
      expect(node.at_css(".pito-channel-item__stats").text).to include("·")
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
      expect(node.css(".pito-stats-counters__cell").last.text.strip).to include("0").and include("Views")
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
      allow(ch).to receive(:videos).and_return(instance_double(ActiveRecord::Associations::CollectionProxy, count: count))
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

    it "orders the counters subscribers → videos → views" do
      node = render_with_video_count(channel_with_videos(3))
      texts = node.css(".pito-stats-counters__cell").map(&:text)
      subs_idx  = texts.index { |t| t.include?("Subs") }
      vids_idx  = texts.index { |t| t.include?("Vids") }
      views_idx = texts.index { |t| t.include?("Views") }
      expect(subs_idx).to be < vids_idx
      expect(vids_idx).to be < views_idx
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
