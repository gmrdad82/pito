require "rails_helper"

# Phase 27 §01f — Show page additions.
#
# The show page must:
#   - Render the OwnedPlatformsChipListComponent in the "owned on"
#     cell of the local-fields table.
#   - Carry the [edit ownership] bracketed link next to the chip list,
#     wired to /games/:slug/platform_ownerships/edit.
#   - Render the muted "(not owned on any platform)" placeholder when
#     the game has zero ownership rows.
#   - Render one bracketed chip per owned platform, alphabetical.
RSpec.describe "Games show — ownership UI (01f)", type: :request do
  let!(:game) { create(:game, :synced, title: "Zelda BotW", igdb_slug: "zelda") }

  describe "no ownership rows" do
    it "renders the muted placeholder in the owned-on cell" do
      get game_path(game)
      expect(response.body).to include("(not owned on any platform)")
    end

    it "still renders the [edit ownership] link" do
      get game_path(game)
      expect(response.body).to include(edit_game_platform_ownerships_path(game))
      expect(response.body).to match(/\[<span class="bl">edit ownership<\/span>\]/)
    end
  end

  describe "with ownership rows" do
    let!(:ps5)   { create(:platform, name: "PS5",   slug: "ps5") }
    let!(:steam) { create(:platform, name: "Steam", slug: "steam") }

    before do
      create(:game_platform_ownership, game: game, platform: steam)
      create(:game_platform_ownership, game: game, platform: ps5)
    end

    it "renders one bracketed chip per owned platform" do
      get game_path(game)
      # Two chips: PS5 + Steam (alphabetical, case-insensitive).
      ps5_idx   = response.body.index('<span class="bl">PS5</span>')
      steam_idx = response.body.index('<span class="bl">Steam</span>')
      expect(ps5_idx).not_to be_nil
      expect(steam_idx).not_to be_nil
      expect(ps5_idx).to be < steam_idx
    end

    it "links each chip to /games?filters=<slug>,owned" do
      get game_path(game)
      expect(response.body).to include("/games?filters=ps5%2Cowned")
      expect(response.body).to include("/games?filters=steam%2Cowned")
    end

    it "drops the muted placeholder" do
      get game_path(game)
      expect(response.body).not_to include("(not owned on any platform)")
    end

    it "still renders the [edit ownership] link" do
      get game_path(game)
      expect(response.body).to include(edit_game_platform_ownerships_path(game))
    end

    it "never emits data-turbo-confirm anywhere on the show page" do
      get game_path(game)
      expect(response.body).not_to include("data-turbo-confirm")
    end
  end

  describe "edit ownership entry-point shape" do
    it "uses the bracketed-link convention" do
      get game_path(game)
      expect(response.body).to match(/\[<span class="bl">edit ownership<\/span>\]/)
    end

    it "does NOT render a red destructive class on the link" do
      get game_path(game)
      # The link is an editor entry-point, not a destructive action.
      link_html = response.body[/<a[^>]*edit_game_platform_ownerships|edit ownership/m]
      expect(link_html).not_to include("text-danger")
    end
  end
end
