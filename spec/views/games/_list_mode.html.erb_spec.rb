require "rails_helper"

# Phase 27 — 01d. List display mode partial (post-polish).
#
# Flat alphabetically-sorted table. The earlier letter-group heading
# rows (`<tr class="letter-head">`) were removed during the
# 2026-05-11 polish pass because their `background: #fff` rendered as
# harsh white spacer bars under the dark theme — users read them as
# unexplained whitespace, not as section dividers. Sort key still
# buckets non-alphabetic titles to the bottom but no headings render.
#
# Columns (locked):
#   cover | title | release year | rating | platforms owned | genres | status
RSpec.describe "games/_list_mode.html.erb", type: :view do
  def render_list(games)
    render partial: "games/list_mode", locals: { games: games }
  end

  describe "happy path" do
    it "renders the seven table headers in the locked column order" do
      create(:game, :synced, title: "Alpha", igdb_id: 4_100_001,
             igdb_slug: "alpha-list")
      render_list(Game.all)

      headers = rendered.scan(%r{<th>([^<]*)</th>}).flatten
      expect(headers).to eq([
        "", "title", "release year", "rating",
        "platforms owned", "genres", "status"
      ])
    end

    it "links each title to /games/:slug without inline year" do
      game = create(:game, :synced, title: "Linked Game", igdb_id: 4_100_031,
                    igdb_slug: "linked-list-game", release_year: 2022)
      render_list(Game.all)

      expect(rendered).to include(%(href="#{game_path(game)}"))
      expect(rendered).to include("Linked Game")
      # Title cell is bare — no `(2022)` suffix glued to the title.
      title_cell_match = rendered[%r{<td class="title-cell">.*?</td>}m]
      expect(title_cell_match).not_to include("(2022)")
      expect(title_cell_match).not_to include("2022")
    end

    it "renders the release year in its own muted column" do
      create(:game, :synced, title: "Yearful", igdb_id: 4_100_041,
             igdb_slug: "yearful-list", release_year: 2018)
      render_list(Game.all)

      year_cell = rendered[%r{<td class="release-year-cell[^"]*"[^>]*>.*?</td>}m]
      expect(year_cell).to include("2018")
      expect(year_cell).to include("text-muted")
    end

    it "renders the rating with a U+2605 star glyph in its own column" do
      create(:game, :synced, title: "Rated Hit", igdb_id: 4_100_051,
             igdb_slug: "rated-hit-list", igdb_rating: 93.5)
      render_list(Game.all)

      rating_cell = rendered[%r{<td class="rating-cell[^"]*"[^>]*>.*?</td>}m]
      expect(rating_cell).to include("★")
      # `format_game_rating` zero-pads to two digits via `.to_i`.
      expect(rating_cell).to include("93")
    end

    it "stamps data-display-mode=\"list\" on the section" do
      render_list(Game.none)
      expect(rendered).to include('data-display-mode="list"')
    end
  end

  describe "no letter-group spacer rows" do
    it "does not render `tr.letter-head` rows even with multiple buckets" do
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_100_011,
             igdb_slug: "apex-legends-list")
      create(:game, :synced, title: "Borderlands", igdb_id: 4_100_012,
             igdb_slug: "borderlands-list")
      create(:game, :synced, title: "Cuphead", igdb_id: 4_100_014,
             igdb_slug: "cuphead-list")

      render_list(Game.all)

      expect(rendered).not_to include('class="letter-head"')
      expect(rendered).not_to include("data-letter=")
      expect(rendered).not_to include("position: sticky")
      # And no hard white background bars — only the themed border token.
      expect(rendered).not_to include("background: #fff")
    end

    it "still sorts titles alphabetically across buckets" do
      create(:game, :synced, title: "Borderlands", igdb_id: 4_100_012,
             igdb_slug: "borderlands-list")
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_100_011,
             igdb_slug: "apex-legends-list")
      create(:game, :synced, title: "Cuphead", igdb_id: 4_100_013,
             igdb_slug: "cuphead-list")

      render_list(Game.all)

      apex_pos = rendered.index("Apex Legends")
      border_pos = rendered.index("Borderlands")
      cup_pos = rendered.index("Cuphead")

      expect(apex_pos).to be < border_pos
      expect(border_pos).to be < cup_pos
    end
  end

  describe "genres column — primary genre only" do
    it "renders a single short-form name (not a comma-joined list)" do
      game = create(:game, :synced, title: "Multi Genre", igdb_id: 4_200_010,
                    igdb_slug: "multi-genre-list")
      rpg = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_311)
      adv = create(:genre, name: "Adventure", igdb_id: 9_312)
      shooter = create(:genre, name: "Shooter", igdb_id: 9_313)
      create(:game_genre, game: game, genre: rpg)
      create(:game_genre, game: game, genre: adv)
      create(:game_genre, game: game, genre: shooter)

      render_list(Game.all)

      genres_cell = rendered[%r{<td class="genres-cell"[^>]*>.*?</td>}m]
      # Exactly one genre token surfaces — no comma-joined list.
      expect(genres_cell).not_to include(", ")
    end

    it "applies the short-form mapping (Role-playing (RPG) → RPG)" do
      game = create(:game, :synced, title: "RPG Game", igdb_id: 4_200_001,
                    igdb_slug: "rpg-list-game")
      rpg = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_301)
      create(:game_genre, game: game, genre: rpg)

      render_list(Game.all)

      expect(rendered).to include("RPG")
      expect(rendered).not_to include("Role-playing (RPG)")
    end

    it "renders unmapped genre names as-is" do
      game = create(:game, :synced, title: "Adventure Game", igdb_id: 4_200_002,
                    igdb_slug: "adventure-list-game")
      adventure = create(:genre, name: "Adventure", igdb_id: 9_302)
      create(:game_genre, game: game, genre: adventure)

      render_list(Game.all)

      expect(rendered).to include("Adventure")
    end

    it "renders an em-dash when the game has no genres" do
      create(:game, :synced, title: "Bare Game", igdb_id: 4_200_003,
             igdb_slug: "bare-list-game")
      render_list(Game.all)

      genres_cell = rendered[%r{<td class="genres-cell"[^>]*>.*?</td>}m]
      expect(genres_cell).to include("—")
    end
  end

  describe "edge cases" do
    it "renders gracefully when a game has no release_year / rating / genres" do
      create(:game, title: "Bare Row", igdb_id: nil)

      expect { render_list(Game.all) }.not_to raise_error
      # Status falls back to `unreleased` when release_date is absent.
      expect(rendered).to include("unreleased")
      # All three "empty" cells render an em-dash placeholder.
      expect(rendered.scan("—").length).to be >= 3
    end

    it "renders the theme-aware SVG fallback pair when a game has no cover_image_id" do
      create(:game, title: "No Cover", igdb_id: nil)
      render_list(Game.all)

      # Plain-text sentinel is GONE — replaced by two image tags the CSS
      # toggles via `<html data-theme>` (see `Games::CoverComponent`).
      expect(rendered).not_to include("[no cover]")
      expect(rendered).to include("game-cover-fallback--light")
      expect(rendered).to include("game-cover-fallback--dark")
      expect(rendered).to match(%r{game_cover_fallback_shelf_light(-[a-f0-9]+)?\.svg})
      expect(rendered).to match(%r{game_cover_fallback_shelf_dark(-[a-f0-9]+)?\.svg})
    end

    it "sinks non-alphabetic titles to the bottom of the sort order" do
      create(:game, :synced, title: "2048", igdb_id: 4_101_001,
             igdb_slug: "two-zero-list")
      create(:game, :synced, title: "Apex", igdb_id: 4_101_003,
             igdb_slug: "apex-sink-list")

      render_list(Game.all)

      expect(rendered.index("Apex")).to be < rendered.index("2048")
    end
  end

  describe "empty state" do
    it "shows the muted no-match copy when given an empty relation" do
      render_list(Game.none)
      expect(rendered).to include("no games match this filter.")
      expect(rendered).not_to include('class="letter-head"')
      expect(rendered).not_to include('class="game-row"')
    end
  end
end
