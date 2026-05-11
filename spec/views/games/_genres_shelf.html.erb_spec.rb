require "rails_helper"

# Phase 27 follow-up — the genres shelf renders the short-form
# display name in the tile caption and the cover-block legend, while
# the `title=` attribute keeps the canonical IGDB name so the tooltip
# disambiguates the abbreviation on hover.
RSpec.describe "games/_genres_shelf.html.erb", type: :view do
  def render_shelf(genres)
    render partial: "games/genres_shelf", locals: { genres: genres }
  end

  describe "short-form display map" do
    it "renders 'RPG' in the caption when the genre is 'Role-playing (RPG)'" do
      genre = create(:genre, name: "Role-playing (RPG)", igdb_id: 9_101)
      render_shelf(Genre.where(id: genre.id))

      # Caption (short form).
      expect(rendered).to match(%r{<div class="tile-caption"[^>]*>\s*RPG\s*</div>})
      # Cover-block legend uses the lowercased short form.
      expect(rendered).to include("[rpg]")
      # The `title=` attribute keeps the canonical long name.
      expect(rendered).to include('title="Role-playing (RPG)"')
    end

    it "renders 'MMO' for both IGDB spellings" do
      genre_no_paren = create(:genre, name: "Massively Multiplayer Online",
                                       igdb_id: 9_102)
      genre_paren    = create(:genre, name: "Massively Multiplayer Online (MMO)",
                                       igdb_id: 9_103)
      render_shelf(Genre.where(id: [ genre_no_paren.id, genre_paren.id ]))

      # The caption renders as `MMO` twice (one tile per row).
      expect(rendered.scan(%r{<div class="tile-caption"[^>]*>\s*MMO\s*</div>}).length).to eq(2)
    end

    it "renders 'Hack & Slash' for the long 'Hack and slash/Beat \\'em up'" do
      genre = create(:genre, name: "Hack and slash/Beat 'em up", igdb_id: 9_104)
      render_shelf(Genre.where(id: genre.id))

      expect(rendered).to include("Hack &amp; Slash")
    end
  end

  describe "passthrough for unmapped genres" do
    it "renders the full IGDB name when no short-form is registered" do
      genre = create(:genre, name: "Adventure", igdb_id: 9_201)
      render_shelf(Genre.where(id: genre.id))

      expect(rendered).to match(%r{<div class="tile-caption"[^>]*>\s*Adventure\s*</div>})
      expect(rendered).to include("[adventure]")
      expect(rendered).to include('title="Adventure"')
    end
  end

  describe "empty state" do
    it "shows the muted placeholder when no genres are provided" do
      render_shelf(Genre.none)
      expect(rendered).to include("(no genres yet)")
    end
  end
end
