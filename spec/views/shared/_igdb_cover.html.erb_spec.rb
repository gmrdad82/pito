require "rails_helper"

# Phase 27 cover-fallback sweep — the shared IGDB cover renderer
# (used on games show / edit / platform_ownerships edit) renders
# the same theme-aware dual-image SVG fallback as
# `Games::CoverComponent` and `games/_tile.html.erb` when the
# game has no `cover_image_id`. The legacy plain-text
# `[no cover]` sentinel is gone from this code path.
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

    it "does NOT emit the fallback SVG pair" do
      render_igdb_cover(game)
      expect(rendered).not_to include("game-cover-fallback--light")
      expect(rendered).not_to include("game-cover-fallback--dark")
    end
  end

  describe "edge: game with no cover_image_id (theme-aware SVG fallback)" do
    let(:bare_game) do
      create(:game, title: "No Cover", igdb_id: nil)
    end

    before { render_igdb_cover(bare_game) }

    it "does NOT render the legacy plain-text [no cover] sentinel" do
      expect(rendered).not_to include("[no cover]")
    end

    it "renders the light-theme fallback <img>" do
      expect(rendered).to include("game-cover-fallback--light")
      expect(rendered).to match(%r{game_cover_fallback_grid_light(-[a-f0-9]+)?\.svg})
    end

    it "renders the dark-theme fallback <img>" do
      expect(rendered).to include("game-cover-fallback--dark")
      expect(rendered).to match(%r{game_cover_fallback_grid_dark(-[a-f0-9]+)?\.svg})
    end

    it "sets alt='no cover available' on both fallback images" do
      expect(rendered.scan(%r{alt="no cover available"}).length).to eq(2)
    end

    it "marks each fallback image with its data-theme value" do
      expect(rendered).to include('data-theme="light"')
      expect(rendered).to include('data-theme="dark"')
    end
  end
end
