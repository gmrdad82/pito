# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::SimilarGamesComponent do
  let(:game) { create(:game, title: "Shadow of the Colossus") }

  GameResult2 = Struct.new(:game, :score, :distance, keyword_init: true)

  def render_component
    render_inline(described_class.new(game: game))
  end

  before do
    allow(Pito::Recommendations).to receive(:similar_games).and_return([])
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

  # ── Similar games section ──────────────────────────────────────────────────

  describe "with similar games" do
    let(:sg1) { create(:game, title: "Ico") }
    let(:sg2) { create(:game, title: "The Last Guardian") }

    let(:similar_results) do
      [
        GameResult2.new(game: sg1, score: 88, distance: 0.12),
        GameResult2.new(game: sg2, score: 74, distance: 0.26)
      ]
    end

    before do
      allow(Pito::Recommendations).to receive(:similar_games)
        .with(game, limit: 6)
        .and_return(similar_results)
    end

    it "renders the similar-games strip" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__similar-games-strip")).not_to be_empty
    end

    it "renders a card for each similar game" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__similar-game-card").length).to eq(2)
    end

    it "renders each game title" do
      node = render_component
      titles = node.css(".pito-game-enhanced-message__similar-game-title").map(&:text).map(&:strip)
      expect(titles).to include("Ico", "The Last Guardian")
    end

    it "does NOT render a channel grid" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__channel-grid")).to be_empty
    end
  end

  # ── Empty state ────────────────────────────────────────────────────────────

  describe "when there are no similar games" do
    it "does not render the strip" do
      node = render_component
      expect(node.css(".pito-game-enhanced-message__similar-games-strip")).to be_empty
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
