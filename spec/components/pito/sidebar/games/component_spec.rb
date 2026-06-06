# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Games::Component do
  # Minimal stub mimicking the Game model's public API used by the component.
  GameStub = Struct.new(:id, :title, keyword_init: true)

  let(:lies_of_p)      { GameStub.new(id: 1, title: "Lies of P") }
  let(:hollow_knight)  { GameStub.new(id: 2, title: "Hollow Knight") }
  let(:celeste)        { GameStub.new(id: 3, title: "Celeste") }

  describe "game rows" do
    it "renders a .pito-game-row for each game" do
      node = render_inline(
        described_class.new(games: [ lies_of_p, hollow_knight ], mode: :show)
      )
      expect(node.css(".pito-game-row").size).to eq(2)
    end

    it "embeds the game id as data-game-id on each row" do
      node = render_inline(
        described_class.new(games: [ lies_of_p, hollow_knight ], mode: :show)
      )
      ids = node.css(".pito-game-row").map { |el| el["data-game-id"].to_i }
      expect(ids).to contain_exactly(1, 2)
    end

    it "renders the game title in each row" do
      node = render_inline(
        described_class.new(games: [ lies_of_p, celeste ], mode: :show)
      )
      expect(node.to_html).to include("Lies of P")
      expect(node.to_html).to include("Celeste")
    end

    it "renders the game id as a '#N' label" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      expect(node.to_html).to include("#1")
    end
  end

  describe "controller mount point" do
    it "mounts pito--games-nav controller on the outer div" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      controller_el = node.css("[data-controller='pito--games-nav']")
      expect(controller_el).not_to be_empty
    end

    it "passes the mode as a data-pito--games-nav-mode-value attribute" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :delete)
      )
      el = node.css("[data-controller='pito--games-nav']").first
      expect(el["data-pito--games-nav-mode-value"]).to eq("delete")
    end

    it "passes mode 'show' for show mode" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      el = node.css("[data-controller='pito--games-nav']").first
      expect(el["data-pito--games-nav-mode-value"]).to eq("show")
    end
  end

  describe "empty state" do
    it "renders no game rows when games is empty" do
      node = render_inline(
        described_class.new(games: [], mode: :show)
      )
      expect(node.css(".pito-game-row")).to be_empty
    end

    it "renders a non-empty empty-state paragraph when games is empty" do
      node = render_inline(
        described_class.new(games: [], mode: :show)
      )
      expect(node.css("p").text).not_to be_empty
    end
  end
end
