require "rails_helper"

# Phase 27 — 01d. Grid display mode partial (default).
#
# Extracted from the legacy `all-games` section in
# `games/index.html.erb`. Renders the existing tile grid with
# `data-keyboard-grid="true"` so the global keyboard controller
# walks it as a tile grid.
RSpec.describe "games/_grid_mode.html.erb", type: :view do
  describe "happy path" do
    it "stamps data-display-mode=\"grid\" on the section" do
      render partial: "games/grid_mode", locals: { games: [] }
      expect(rendered).to include('data-display-mode="grid"')
    end

    it "carries the keyboard-grid opt-in flag when at least one game renders" do
      game = create(:game, :synced, title: "Tile Game",
                    igdb_id: 4_000_001, igdb_slug: "tile-game")
      render partial: "games/grid_mode", locals: { games: Game.where(id: game.id) }

      expect(rendered).to include('data-keyboard-grid="true"')
      expect(rendered).to include("Tile Game")
      expect(rendered).to include("data-tile-game-id=\"#{game.id}\"")
    end

    it "renders the post-polish heading 'all' (Fix 8)" do
      render partial: "games/grid_mode", locals: { games: [] }
      expect(rendered).to include(">all<")
      expect(rendered).not_to include(">all games<")
    end
  end

  describe "empty state" do
    it "renders the muted no-match copy when given an empty relation" do
      render partial: "games/grid_mode", locals: { games: Game.none }
      expect(rendered).to include("no games match this filter.")
      expect(rendered).not_to include('data-keyboard-grid="true"')
    end
  end
end
