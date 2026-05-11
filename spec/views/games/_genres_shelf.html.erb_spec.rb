require "rails_helper"

# Phase 27 §01c-v2 — Outer Genres shelf (nested).
#
# Supersedes the v1 flat-tile spec. The outer shelf renders a single
# `<section data-shelf="outer-genres">` with an `<h2>` heading, then
# iterates one `<section class="sub-shelf--genre">` per genre. Empty
# buckets are hidden end-to-end (no muted placeholder, no `<h2>`).
RSpec.describe "games/_genres_shelf.html.erb", type: :view do
  def render_shelf(genres)
    render partial: "games/genres_shelf", locals: { genres: genres }
  end

  describe "happy: outer shelf with non-empty genres" do
    let!(:adventure) { create(:genre, name: "Adventure", igdb_id: 9_201, slug: "adventure") }
    let!(:rpg)       { create(:genre, name: "RPG",       igdb_id: 9_202, slug: "rpg") }
    let!(:game_a)    { create(:game, :synced, title: "Anachronox") }
    let!(:game_b)    { create(:game, :synced, title: "Baldur's Gate") }

    before do
      game_a.genres << adventure
      game_b.genres << rpg
    end

    it "renders the outer-shelf <section> with the outer-genres data hook" do
      render_shelf(Genre.where(id: [ adventure.id, rpg.id ]))
      expect(rendered).to include('data-shelf="outer-genres"')
      expect(rendered).to match(%r{<section[^>]*shelf--genres outer-shelf})
    end

    it "renders one <h2> labelled 'genres'" do
      render_shelf(Genre.where(id: [ adventure.id, rpg.id ]))
      expect(rendered).to match(%r{<h2[^>]*>\s*genres\s*</h2>})
    end

    it "renders one sub-shelf per genre" do
      render_shelf(Genre.where(id: [ adventure.id, rpg.id ]))
      expect(rendered.scan('data-shelf="genre-sub"').length).to eq(2)
    end

    it "renders an <h3> per sub-shelf with the genre's display label" do
      render_shelf(Genre.where(id: [ adventure.id, rpg.id ]))
      # Phase 27 follow-up (2026-05-11) — lowercase rule. "Adventure"
      # downcases; "RPG" stays upper as an acronym.
      expect(rendered).to match(%r{<h3[^>]*>\s*adventure\s*</h3>})
      expect(rendered).to match(%r{<h3[^>]*>\s*RPG\s*</h3>})
    end
  end

  describe "happy: short-form display map in sub-shelf <h3>" do
    let!(:game) { create(:game, :synced, title: "Persona 5") }

    it "renders 'RPG' in the <h3> when the genre is 'Role-playing (RPG)'" do
      genre = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_101)
      game.genres << genre
      render_shelf(Genre.where(id: genre.id))

      # Sub-shelf <h3> carries the short-form name.
      expect(rendered).to match(%r{<h3[^>]*>\s*RPG\s*</h3>})
    end

    it "passthrough: lowercases the full IGDB name when no short-form is registered" do
      genre = create(:genre, name: "Adventure", igdb_id: 9_201)
      game.genres << genre
      render_shelf(Genre.where(id: genre.id))

      expect(rendered).to match(%r{<h3[^>]*>\s*adventure\s*</h3>})
    end
  end

  describe "edge: empty input" do
    it "renders NOTHING when no genres are provided" do
      render_shelf(Genre.none)
      expect(rendered.strip).to eq("")
    end

    it "does NOT render the legacy '(no genres yet)' placeholder" do
      render_shelf(Genre.none)
      expect(rendered).not_to include("(no genres yet)")
    end

    it "does NOT render an <h2> labelled 'genres' when input is empty" do
      render_shelf(Genre.none)
      expect(rendered).not_to match(%r{<h2[^>]*>\s*genres\s*</h2>})
    end

    it "does NOT render an outer-shelf <section> when input is empty" do
      render_shelf(Genre.none)
      expect(rendered).not_to include('data-shelf="outer-genres"')
    end
  end

  describe "polish: hairline between consecutive sub-shelves (2026-05-11)" do
    let!(:adventure) { create(:genre, name: "Adventure", igdb_id: 9_301, slug: "adventure") }
    let!(:rpg)       { create(:genre, name: "RPG",       igdb_id: 9_302, slug: "rpg") }
    let!(:game_a)    { create(:game, :synced, title: "Anachronox") }
    let!(:game_b)    { create(:game, :synced, title: "Baldur's Gate") }

    before do
      game_a.genres << adventure
      game_b.genres << rpg
    end

    it "emits a scoped CSS rule that draws a 1px border-top between sub-shelves" do
      render_shelf(Genre.where(id: [ adventure.id, rpg.id ]))
      expect(rendered).to include('section[data-shelf="outer-genres"] > section.sub-shelf:not(:first-of-type)')
      expect(rendered).to include("border-top: 1px solid var(--color-border)")
    end

    it "does NOT draw the hairline when only one sub-shelf renders" do
      # The CSS rule is scoped to `:not(:first-of-type)` so a single
      # sub-shelf is unaffected; verify by structure (only one
      # `data-shelf=\"genre-sub\"` node renders).
      render_shelf(Genre.where(id: adventure.id))
      expect(rendered.scan('data-shelf="genre-sub"').length).to eq(1)
    end
  end

  describe "flaw: no v1 flat-tile remnants" do
    let!(:adventure) { create(:genre, name: "Adventure", igdb_id: 9_201, slug: "adventure") }
    let!(:game)      { create(:game, :synced, title: "Tunic") }

    before { game.genres << adventure }

    it "does NOT render `.tile--shelf` anchors (v1 genre-name tile)" do
      render_shelf(Genre.where(id: adventure.id))
      # The v1 design rendered a `<a class="tile tile--shelf">` for the
      # whole genre. v2 puts game tiles (Games::CoverComponent) inside.
      expect(rendered).not_to include('class="tile tile--shelf"')
    end

    it "does NOT render a `[adventure]` bracketed legend block" do
      render_shelf(Genre.where(id: adventure.id))
      # The v1 design printed `[<short_name>]` inside a neutral cover block.
      expect(rendered).not_to include("[adventure]")
    end

    it "does NOT render the v1 `tile-caption` divs (replaced by <h3> + cover component)" do
      render_shelf(Genre.where(id: adventure.id))
      expect(rendered).not_to match(%r{<div class="tile-caption"[^>]*>\s*Adventure\s*</div>})
    end
  end
end
