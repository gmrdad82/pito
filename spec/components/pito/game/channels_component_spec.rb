# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::ChannelsComponent do
  let(:game) { create(:game, title: "Shadow of the Colossus") }

  ChannelResult2 = Struct.new(:channel, :score, :distance, keyword_init: true)

  def build_channel(handle:, title:)
    Channel.new(handle: handle, title: title, youtube_channel_id: "UC#{SecureRandom.hex(4)}")
  end

  def render_component
    render_inline(described_class.new(game: game))
  end

  before do
    allow(Pito::Recommendations).to receive(:channels_for).and_return([])
  end

  # ── Intro ──────────────────────────────────────────────────────────────────

  describe "intro line" do
    it "renders a non-blank intro line" do
      node = render_component
      intro = node.at_css(".pito-game-enhanced-message__intro")
      expect(intro).to be_present
      expect(intro.text.strip).not_to be_empty
    end

    it "renders without surrounding curly quotes" do
      html = render_component.to_html
      expect(html).not_to include("“")
      expect(html).not_to include("”")
    end
  end

  # ── Channel section ────────────────────────────────────────────────────────

  describe "with channel results" do
    let(:ch1) { build_channel(handle: "gamegrumps", title: "Game Grumps") }
    let(:ch2) { build_channel(handle: "markiplier", title: "Markiplier") }

    let(:channel_results) do
      [
        ChannelResult2.new(channel: ch1, score: 78, distance: 0.22),
        ChannelResult2.new(channel: ch2, score: 65, distance: 0.35)
      ]
    end

    before do
      allow(Pito::Recommendations).to receive(:channels_for)
        .with(game, include_all: true)
        .and_return(channel_results)
    end

    it "renders the channel grid" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid")).not_to be_empty
    end

    it "renders the @handle for each channel" do
      node = render_component
      handles = node.css(".pito-channel-item__handle").map(&:text).map(&:strip)
      expect(handles).to include("@gamegrumps", "@markiplier")
    end

    it "renders a score bar for each channel" do
      node = render_component
      score_bars = node.css(".pito-channel-item__score .pito-score-bar")
      expect(score_bars.length).to eq(2)
    end

    it "does NOT render a similar-games strip" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__similar-games-strip")).to be_empty
    end
  end

  # ── Empty state ────────────────────────────────────────────────────────────

  describe "when there are no channel results" do
    it "does not render the channel grid" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid")).to be_empty
    end

    it "still renders the intro" do
      node = render_component
      expect(node.at_css(".pito-game-enhanced-message__intro")).to be_present
    end

    it "does not raise" do
      expect { render_component }.not_to raise_error
    end
  end
end
