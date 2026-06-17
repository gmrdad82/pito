# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::EnhancedComponent do
  let(:game) { create(:game, title: "Shadow of the Colossus") }

  # ── Stub helpers ────────────────────────────────────────────────────────────

  # Build a minimal channel stub (uses real Channel model so at_handle works).
  def build_channel(handle:, title:)
    Channel.new(handle: handle, title: title, youtube_channel_id: "UC#{SecureRandom.hex(4)}")
  end

  # ChannelRecommendation::Result struct shape.
  ChannelResult = Struct.new(:channel, :score, :distance, keyword_init: true)

  # Pito::Recommendations::Result struct shape (similar games direction).
  GameResult = Struct.new(:game, :score, :distance, keyword_init: true)

  def render_component
    render_inline(described_class.new(game: game))
  end

  # ── Intro ──────────────────────────────────────────────────────────────────

  describe "intro line" do
    before do
      allow(Pito::Recommendations).to receive(:channels_for).and_return([])
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
    end

    it "renders without surrounding curly quotes" do
      html = render_component.to_html
      expect(html).not_to include("“")
      expect(html).not_to include("”")
    end

    it "renders a non-blank intro line" do
      node = render_component
      intro = node.at_css(".pito-game-enhanced-message__intro")
      expect(intro).to be_present
      expect(intro.text.strip).not_to be_empty
    end
  end

  # ── Channel section ────────────────────────────────────────────────────────

  describe "channel matches" do
    let(:ch1) { build_channel(handle: "gamegrumps", title: "Game Grumps") }
    let(:ch2) { build_channel(handle: "markiplier", title: "Markiplier") }

    let(:channel_results) do
      [
        ChannelResult.new(channel: ch1, score: 78, distance: 0.22),
        ChannelResult.new(channel: ch2, score: 65, distance: 0.35)
      ]
    end

    before do
      allow(Pito::Recommendations).to receive(:channels_for).with(game, include_all: true)
                                                            .and_return(channel_results)
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
    end

    it "renders the channel section header" do
      node = render_component
      headers = node.css(".pito-game-enhanced-message__section-header")
      expect(headers).not_to be_empty
    end

    it "renders the @handle for each channel (via ItemComponent)" do
      node = render_component
      handles = node.css(".pito-channel-item__handle").map(&:text).map(&:strip)
      expect(handles).to include("@gamegrumps", "@markiplier")
    end

    it "renders the title for each channel (via ItemComponent)" do
      node = render_component
      titles = node.css(".pito-channel-item__title").map(&:text).map(&:strip)
      expect(titles).to include("Game Grumps", "Markiplier")
    end

    it "renders a .pito-score-bar element for each channel (via ItemComponent)" do
      node = render_component
      score_bars = node.css(".pito-channel-item__score .pito-score-bar")
      expect(score_bars.length).to eq(2)
    end

    it "passes the result score to each ScoreBarComponent (Part 1 regression guard)" do
      node = render_component
      score_bars = node.css(".pito-channel-item__score .pito-score-bar")
      scores = score_bars.map { |el| el["data-score"] }
      expect(scores).to include("78", "65")
    end

    it "does not render a [visit] link in the channel grid (show_visit: false)" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid .pito-channel-visit")).to be_empty
    end

    it "does not render stat rows in the channel grid (show_stats: false by default)" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid .pito-channel-item__stats")).to be_empty
      expect(node.css(".pito-game-enhanced-message__channel-grid .pito-channel-item__stat")).to be_empty
    end
  end

  # ── Similar games section ──────────────────────────────────────────────────

  describe "similar games" do
    let(:sg1) { create(:game, title: "Ico") }
    let(:sg2) { create(:game, title: "The Last Guardian") }

    let(:similar_results) do
      [
        GameResult.new(game: sg1, score: 88, distance: 0.12),
        GameResult.new(game: sg2, score: 74, distance: 0.26)
      ]
    end

    before do
      allow(Pito::Recommendations).to receive(:channels_for).and_return([])
      allow(Pito::Recommendations).to receive(:similar_games).with(game, limit: 5)
                                                             .and_return(similar_results)
    end

    it "renders the similar-games section header" do
      node = render_component
      headers = node.css(".pito-game-enhanced-message__section-header")
      expect(headers).not_to be_empty
    end

    it "renders a card for each similar game" do
      node = render_component
      cards = node.css(".pito-game-enhanced-message__similar-game-card")
      expect(cards.length).to eq(2)
    end

    it "renders each game title" do
      node = render_component
      titles = node.css(".pito-game-enhanced-message__similar-game-title").map(&:text).map(&:strip)
      expect(titles).to include("Ico", "The Last Guardian")
    end

    it "renders the #-prefixed db id for each similar game" do
      node = render_component
      ids = node.css(".pito-game-enhanced-message__similar-game-id").map(&:text).map(&:strip)
      expect(ids).to include("##{sg1.id}", "##{sg2.id}")
    end

    it "renders a data-game-id attribute on each card" do
      node = render_component
      data_ids = node.css(".pito-game-enhanced-message__similar-game-card").map { |el| el["data-game-id"] }
      expect(data_ids).to include(sg1.id.to_s, sg2.id.to_s)
    end

    it "puts the id and title on one line separated by ·" do
      node = render_component
      lines = node.css(".pito-game-enhanced-message__similar-game-line")
      expect(lines).not_to be_empty
      lines.each do |line|
        expect(line.text.gsub(/\s+/, " ").strip).to match(/\A#\d+ · .+/)
      end
    end

    context "when a similar game has no cover art attached" do
      it "renders a placeholder div instead of an img tag" do
        node = render_component
        cards = node.css(".pito-game-enhanced-message__similar-game-card")
        # No cover art → placeholder div, not an img
        cards.each do |card|
          expect(card.css("img").length).to eq(0)
          expect(card.at_css(".pito-game-enhanced-message__similar-game-cover--placeholder")).to be_present
        end
      end
    end
  end

  # ── Empty / graceful states ────────────────────────────────────────────────

  describe "graceful empty state" do
    before do
      allow(Pito::Recommendations).to receive(:channels_for).and_return([])
      allow(Pito::Recommendations).to receive(:similar_games).and_return([])
    end

    it "renders the intro even with no recommendations" do
      node = render_component
      intro = node.at_css(".pito-game-enhanced-message__intro")
      expect(intro).to be_present
    end

    it "does not render a channel grid when there are no channel results" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid")).to be_empty
    end

    it "does not render a similar-games strip when there are no similar games" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__similar-games-strip")).to be_empty
    end

    it "does not raise" do
      expect { render_component }.not_to raise_error
    end
  end

  # ── Combined (both sections present) ──────────────────────────────────────

  describe "when both channels and similar games are present" do
    let(:ch) { build_channel(handle: "dunkey", title: "videogamedunkey") }

    let(:sg) { create(:game, title: "Journey") }

    before do
      allow(Pito::Recommendations).to receive(:channels_for)
        .and_return([ ChannelResult.new(channel: ch, score: 90, distance: 0.10) ])
      allow(Pito::Recommendations).to receive(:similar_games)
        .and_return([ GameResult.new(game: sg, score: 85, distance: 0.15) ])
    end

    it "renders both section headers" do
      node = render_component
      headers = node.css(".pito-game-enhanced-message__section-header")
      expect(headers.length).to eq(2)
    end

    it "renders the spacer between sections" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__spacer")).not_to be_empty
    end
  end
end
