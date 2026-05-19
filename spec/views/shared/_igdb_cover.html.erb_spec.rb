require "rails_helper"

# Phase 27 cover-fallback sweep — the shared IGDB cover renderer
# (used on games show / edit / platform_ownerships edit) renders
# the single-dark SVG fallback when the game has no
# `cover_image_id`. The legacy plain-text `[no cover]` sentinel
# is gone, and the previous dual light/dark pair was collapsed to
# one image alongside the 2026-05-19 single-theme cleanup.
RSpec.describe "shared/_igdb_cover.html.erb", type: :view do
  def render_igdb_cover(game, **locals)
    render partial: "shared/igdb_cover", locals: { game: game, **locals }
  end

  describe "happy: game with a cover_image_id" do
    let(:game) do
      create(:game, :synced,
             title: "Covered Game",
             igdb_id: 7_000_001,
             igdb_slug: "covered-game")
    end

    it "renders the IGDB cover URL as an <img>" do
      render_igdb_cover(game)
      expect(rendered).to include(%(alt="Covered Game"))
      expect(rendered).to match(%r{<img[^>]*src="[^"]*igdb[^"]*"})
    end

    it "does NOT emit the fallback SVG" do
      render_igdb_cover(game)
      expect(rendered).not_to include("game-cover-fallback")
    end
  end

  describe "edge: game with no cover_image_id (single-dark SVG fallback)" do
    let(:bare_game) do
      create(:game, title: "No Cover", igdb_id: nil)
    end

    before { render_igdb_cover(bare_game) }

    it "does NOT render the legacy plain-text [no cover] sentinel" do
      expect(rendered).not_to include("[no cover]")
    end

    it "renders the single-dark fallback <img>" do
      expect(rendered).to include("game-cover-fallback")
      expect(rendered).to match(%r{game_cover_fallback_grid_dark(-[a-f0-9]+)?\.svg})
    end

    it "sets alt='no cover available' on the fallback image" do
      expect(rendered.scan(%r{alt="no cover available"}).length).to eq(1)
    end

    it "does NOT emit the dropped theme-variant fallback classes" do
      expect(rendered).not_to include("game-cover-fallback--light")
      expect(rendered).not_to include("game-cover-fallback--dark")
    end

    it "does NOT emit data-theme attributes (theme system removed 2026-05-19)" do
      expect(rendered).not_to include('data-theme="light"')
      expect(rendered).not_to include('data-theme="dark"')
    end

    it "does NOT reference a _light.svg fallback asset" do
      expect(rendered).not_to match(/game_cover_fallback_[a-z]+_light/)
    end
  end
end
