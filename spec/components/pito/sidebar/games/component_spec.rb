# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::Games::Component do
  # Minimal stub mimicking the Game model's public API used by the component.
  # platforms defaults to nil (PlatformTokens.icons_html handles nil gracefully).
  GameStub = Struct.new(:id, :title, :platforms, keyword_init: true) do
    def initialize(id:, title:, platforms: nil)
      super(id:, title:, platforms:)
    end
  end

  let(:lies_of_p)     { GameStub.new(id: 1, title: "Lies of P") }
  let(:hollow_knight) { GameStub.new(id: 2, title: "Hollow Knight") }
  let(:celeste)       { GameStub.new(id: 3, title: "Celeste") }

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

    it "renders the #-prefixed game id right-aligned" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      id_cell = node.css("span.tabular-nums.text-right").first
      expect(id_cell.text.strip).to eq("##{lies_of_p.id}")
    end

    it "renders platform icons when the game has platforms" do
      game = GameStub.new(id: 4, title: "Elden Ring", platforms: [ "PlayStation 5" ])
      node = render_inline(
        described_class.new(games: [ game ], mode: :show)
      )
      expect(node.to_html).to include("pito-platform-icons")
    end

    it "renders no platform icons when the game has no platforms" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      expect(node.to_html).not_to include("pito-platform-icons")
    end
  end

  describe "search input" do
    it "renders a search input with the input target" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      input = node.css("input[data-pito--games-nav-target='input']")
      expect(input).not_to be_empty
    end

    it "renders a list container with the list target" do
      node = render_inline(
        described_class.new(games: [ lies_of_p ], mode: :show)
      )
      list = node.css("[data-pito--games-nav-target='list']")
      expect(list).not_to be_empty
    end

    it "renders a hidden shimmer (dots) indicator with the shimmer target" do
      node    = render_inline(described_class.new(games: [ lies_of_p ], mode: :show))
      shimmer = node.css("[data-pito--games-nav-target='shimmer']")
      expect(shimmer).not_to be_empty
      expect(shimmer.first["class"]).to include("hidden")
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

  describe "native block caret" do
    subject(:node) { render_inline(described_class.new(games: [], mode: :show)) }

    it "styles the search input with the native block caret (.pito-block-caret)" do
      input = node.css("input[data-pito--games-nav-target='input']").first
      expect(input).to be_present
      expect(input["class"]).to include("pito-block-caret")
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
