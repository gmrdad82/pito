require "rails_helper"

# Phase 27 — 01d. List display mode partial.
#
# Alphabetic table grouped by the first letter of the title. Letter
# headings are rendered as `<tr class="letter-head">` rows carrying
# CSS `position: sticky` so they stay pinned during scroll. Empty
# letters are NOT rendered. Non-alphabetic title starts bucket
# into "#".
RSpec.describe "games/_list_mode.html.erb", type: :view do
  def render_list(games)
    render partial: "games/list_mode", locals: { games: games }
  end

  describe "happy path" do
    it "renders the table head with five columns" do
      render_list(Game.none)
      # Empty state path doesn't reach the table; create one row first.
      create(:game, :synced, title: "Alpha", igdb_id: 4_100_001,
             igdb_slug: "alpha-list")
      render_list(Game.all)

      expect(rendered).to include("<th>title</th>")
      expect(rendered).to include("<th>platforms owned</th>")
      expect(rendered).to include("<th>genres</th>")
      expect(rendered).to include("<th>status</th>")
    end

    it "interleaves letter-head rows between alphabetic groups" do
      create(:game, :synced, title: "Apex Legends", igdb_id: 4_100_011,
             igdb_slug: "apex-legends-list")
      create(:game, :synced, title: "Borderlands", igdb_id: 4_100_012,
             igdb_slug: "borderlands-list")
      create(:game, :synced, title: "Astroneer", igdb_id: 4_100_013,
             igdb_slug: "astroneer-list")

      render_list(Game.all)

      # One letter-head per non-empty bucket.
      expect(rendered.scan(/data-letter="A"/).length).to eq(1)
      expect(rendered.scan(/data-letter="B"/).length).to eq(1)
      # Z is absent (no Z game in this scope).
      expect(rendered).not_to include('data-letter="Z"')
    end

    it "carries the `letter-head` class so CSS position:sticky applies" do
      create(:game, :synced, title: "Anything", igdb_id: 4_100_021,
             igdb_slug: "anything-list")

      render_list(Game.all)

      expect(rendered).to include('class="letter-head"')
      # The partial inlines the sticky declaration so it's always live.
      expect(rendered).to include("position: sticky")
    end

    it "links each title to /games/:slug" do
      game = create(:game, :synced, title: "Linked Game", igdb_id: 4_100_031,
                    igdb_slug: "linked-list-game")
      render_list(Game.all)

      expect(rendered).to include(%(href="#{game_path(game)}"))
      expect(rendered).to include("Linked Game")
    end

    it "stamps data-display-mode=\"list\" on the section" do
      render_list(Game.none)
      expect(rendered).to include('data-display-mode="list"')
    end
  end

  describe "short-form genre names" do
    it "renders the short form in the genres column for mapped IGDB names" do
      game = create(:game, :synced, title: "RPG Game", igdb_id: 4_200_001,
                    igdb_slug: "rpg-list-game")
      rpg = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_301)
      create(:game_genre, game: game, genre: rpg)

      render_list(Game.all)

      # The list mode never prints the canonical long name — only the
      # short form lands in the genres column.
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
  end

  describe "edge cases" do
    it "buckets non-alphabetic titles into the '#' group" do
      create(:game, :synced, title: "2048", igdb_id: 4_101_001,
             igdb_slug: "two-zero-list")

      render_list(Game.all)

      expect(rendered).to include('data-letter="#"')
    end

    it "is case-insensitive on the bucket letter" do
      # IGDB titles are normalized capitalized but local-only rows can
      # start lowercase. Bucket key is `.upcase`.
      create(:game, :synced, title: "apex", igdb_id: 4_101_002,
             igdb_slug: "apex-lower-list")
      render_list(Game.all)

      expect(rendered).to include('data-letter="A"')
    end

    it "renders gracefully when a game has no genres / no release_date" do
      create(:game, title: "Bare Row", igdb_id: nil)

      expect { render_list(Game.all) }.not_to raise_error
      # Status falls back to `unreleased` when release_date is absent.
      expect(rendered).to include("unreleased")
    end

    it "renders gracefully when a game has no cover_image_id" do
      create(:game, title: "No Cover", igdb_id: nil)
      render_list(Game.all)
      expect(rendered).to include("[no cover]")
    end
  end

  describe "empty state" do
    it "shows the muted no-match copy when given an empty relation" do
      render_list(Game.none)
      expect(rendered).to include("no games match this filter.")
      expect(rendered).not_to include('class="letter-head"')
    end
  end
end
