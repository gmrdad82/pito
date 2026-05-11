require "rails_helper"

# Phase 27 — 01d. Shelves-by-letter display mode partial.
#
# One horizontal `games/shelf` per first-letter bucket. Empty
# letters are NOT rendered (locked decision in the umbrella). The
# bucket key is the first character `.upcase`, with non-alphabetic
# starts collapsed into "#".
RSpec.describe "games/_shelves_by_letter_mode.html.erb", type: :view do
  def render_shelves(games)
    render partial: "games/shelves_by_letter_mode", locals: { games: games }
  end

  describe "happy path" do
    it "renders one shelf per non-empty letter and hides empty letters" do
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_200_001,
             igdb_slug: "apex-legends-shelf")
      create(:game, :synced, title: "Borderlands", igdb_id: 4_200_002,
             igdb_slug: "borderlands-shelf")

      render_shelves(Game.all)

      # Each existing letter renders a `<h2>` heading via the shared
      # `games/shelf` partial.
      expect(rendered).to include(">A<")
      expect(rendered).to include(">B<")
      # Locked decision — empty letters hidden.
      expect(rendered).not_to include(">Z<")
      expect(rendered).not_to include(">M<")
    end

    it "uses the steam-shelf controller for each shelf" do
      create(:game, :synced, title: "Anything", igdb_id: 4_200_011,
             igdb_slug: "anything-shelf")

      render_shelves(Game.all)

      expect(rendered).to include('data-controller="steam-shelf"')
    end

    it "renders the game tile partial inside each shelf" do
      game = create(:game, :synced, title: "Tile Game", igdb_id: 4_200_021,
                    igdb_slug: "tile-shelf")

      render_shelves(Game.all)

      # Tile uses the existing `games/tile` partial — link to show page.
      expect(rendered).to include(%(href="#{game_path(game)}"))
    end

    it "stamps data-display-mode=\"shelves_by_letter\" on the section" do
      render_shelves(Game.none)
      expect(rendered).to include('data-display-mode="shelves_by_letter"')
    end
  end

  describe "edge cases" do
    it "buckets non-alphabetic titles into '#'" do
      create(:game, :synced, title: "2048", igdb_id: 4_201_001,
             igdb_slug: "two-zero-shelf")

      render_shelves(Game.all)

      expect(rendered).to include(">#<")
    end

    it "buckets case-insensitively (a → A)" do
      create(:game, :synced, title: "apex", igdb_id: 4_201_002,
             igdb_slug: "apex-lower-shelf")

      render_shelves(Game.all)

      expect(rendered).to include(">A<")
      expect(rendered).not_to include(">a<")
    end
  end

  describe "empty state" do
    it "shows the muted no-match copy when given an empty relation" do
      render_shelves(Game.none)
      expect(rendered).to include("no games match this filter.")
      # No shelf wrappers when there's nothing to bucket.
      expect(rendered).not_to include('data-controller="steam-shelf"')
    end
  end
end
