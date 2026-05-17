require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor controller specs
# (revamped 2026-05-12).
#
# Routes:
#
#   GET    /games/:game_id/platform_ownerships/edit  → edit
#   PATCH  /games/:game_id/platform_ownerships       → update
#
# The controller:
#   - Renders one bracketed-checkbox row per IGDB release-platform
#     (union with any platform the user already owns).
#   - Accepts a flat `platform_owned_ids[]` array on PATCH. Every
#     platform absent from the array is treated as not owned.
#   - On update: creates rows for ticked platforms, destroys rows for
#     platforms missing from the array, no-ops on idempotent re-submit.
#   - 422s on invalid input (unknown platform_id, duplicate id).
RSpec.describe "Games::PlatformOwnerships", type: :request do
  let!(:game)  { create(:game, :synced, title: "Test", igdb_slug: "test-game") }
  let!(:ps5)   { create(:platform, name: "PS5",   slug: "ps5") }
  let!(:steam) { create(:platform, name: "Steam", slug: "steam") }
  # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — the original
  # third platform was `gog`; that slug is retired. `xbox` substitutes
  # — still canonical, sorts lexically after `ps5` + `steam` (so the
  # alphabetical-order assertion gets adjusted below).
  let!(:xbox)  { create(:platform, name: "Xbox",  slug: "xbox") }

  before do
    # All three platforms are in the IGDB release set; the user owns
    # none of them yet.
    game.platforms_available << ps5
    game.platforms_available << steam
    game.platforms_available << xbox
  end

  # ------------------------------------------------------------
  # GET /games/:slug/platform_ownerships/edit
  # ------------------------------------------------------------

  describe "GET /games/:slug/platform_ownerships/edit" do
    it "returns 200" do
      get edit_game_platform_ownerships_path(game)
      expect(response).to have_http_status(:ok)
    end

    it "renders one bracketed-checkbox row per platform" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body.scan(/<label class="md-check"/).size).to eq(3)
    end

    it "uses the flat `platform_owned_ids[]` array name on every checkbox" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body.scan(/name="platform_owned_ids\[\]"/).size).to eq(3)
    end

    it "renders rows alphabetical (case-insensitive)" do
      get edit_game_platform_ownerships_path(game)
      ps5_idx   = response.body.index("data-platform-slug=\"ps5\"")
      steam_idx = response.body.index("data-platform-slug=\"steam\"")
      xbox_idx  = response.body.index("data-platform-slug=\"xbox\"")
      expect([ ps5_idx, steam_idx, xbox_idx ])
        .to eq([ ps5_idx, steam_idx, xbox_idx ].sort)
    end

    it "renders the simplified 'ownership' heading (no 'per-platform' prefix)" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body).to match(%r{<h2[^>]*>ownership</h2>})
    end

    it "does not render the dropped subtitle copy" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body).not_to include("tick the platforms you own this game on")
      expect(response.body).not_to include("optional fields (acquired, store, notes)")
    end

    it "carries the [save] submit button" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body).to match(/\[<span class="bl">save<\/span>\]/)
    end

    it "carries the [cancel] back link to game show" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body).to include(game_path(game))
      expect(response.body).to match(/\[<span class="bl">cancel<\/span>\]/)
    end

    it "resolves the game by slug" do
      get "/games/test-game/platform_ownerships/edit"
      expect(response).to have_http_status(:ok)
    end

    it "404s for an unknown slug" do
      get "/games/no-such-game/platform_ownerships/edit"
      expect(response).to have_http_status(:not_found)
    end

    it "renders a row for an owned platform that is NOT in the IGDB release set" do
      orphan_platform = create(:platform, name: "Switch", slug: "switch")
      create(:game_platform_ownership, game: game, platform: orphan_platform)
      get edit_game_platform_ownerships_path(game)
      expect(response.body).to include('data-platform-slug="switch"')
    end

    it "checks the row for a currently-owned platform" do
      create(:game_platform_ownership, game: game, platform: ps5)
      get edit_game_platform_ownerships_path(game)
      checkbox_html = response.body[/<input[^>]+value="#{ps5.id}"[^>]*>/]
      expect(checkbox_html).to include("checked")
    end

    it "leaves the row unchecked for a not-yet-owned platform" do
      get edit_game_platform_ownerships_path(game)
      checkbox_html = response.body[/<input[^>]+value="#{ps5.id}"[^>]*>/]
      expect(checkbox_html).not_to include("checked")
    end

    it "renders the '(no platforms available)' placeholder when the game has zero release-platforms" do
      lonely_game = create(:game, :synced, title: "Lonely", igdb_slug: "lonely")
      get edit_game_platform_ownerships_path(lonely_game)
      expect(response.body).to include("(no platforms available)")
    end

    it "never emits per-row date / store / notes inputs" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body).not_to include('type="date"')
      expect(response.body).not_to include("<textarea")
      expect(response.body).not_to match(/name="[^"]*\[store\]"/)
      expect(response.body).not_to match(/name="[^"]*\[notes\]"/)
      expect(response.body).not_to match(/name="[^"]*\[acquired_at\]"/)
    end
  end

  # ------------------------------------------------------------
  # PATCH /games/:slug/platform_ownerships — happy
  # ------------------------------------------------------------

  describe "PATCH /games/:slug/platform_ownerships — happy" do
    it "creates ownership rows for every id in the array and redirects to show" do
      expect {
        patch game_platform_ownerships_path(game), params: {
          platform_owned_ids: [ ps5.id.to_s, steam.id.to_s ]
        }
      }.to change(GamePlatformOwnership, :count).by(2)

      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to include("ownership updated")
      expect(game.reload.owned_platforms.pluck(:slug)).to match_array(%w[ps5 steam])
    end

    it "destroys the row for a platform missing from the submitted array" do
      create(:game_platform_ownership, game: game, platform: ps5)
      expect {
        patch game_platform_ownerships_path(game), params: { platform_owned_ids: [] }
      }.to change(GamePlatformOwnership, :count).by(-1)

      expect(game.reload.owned_platforms).to be_empty
    end

    it "keeps the row when its platform stays in the submitted array" do
      existing = create(:game_platform_ownership, game: game, platform: ps5)
      expect {
        patch game_platform_ownerships_path(game), params: {
          platform_owned_ids: [ ps5.id.to_s ]
        }
      }.not_to change(GamePlatformOwnership, :count)
      expect(GamePlatformOwnership.exists?(existing.id)).to be(true)
    end

    it "empty submit un-owns everything" do
      create(:game_platform_ownership, game: game, platform: ps5)
      create(:game_platform_ownership, game: game, platform: steam)
      patch game_platform_ownerships_path(game), params: { platform_owned_ids: [] }
      expect(game.reload.owned_platforms).to be_empty
    end

    it "no-op when the array is empty and no rows existed" do
      expect {
        patch game_platform_ownerships_path(game), params: { platform_owned_ids: [] }
      }.not_to change(GamePlatformOwnership, :count)
      expect(response).to redirect_to(game_path(game))
    end

    it "omitting the param entirely un-owns everything (treated as empty array)" do
      create(:game_platform_ownership, game: game, platform: ps5)
      patch game_platform_ownerships_path(game), params: {}
      expect(game.reload.owned_platforms).to be_empty
    end

    it "accepts mixed string/integer ids in the array" do
      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ ps5.id, steam.id.to_s ]
      }
      expect(game.reload.owned_platforms.pluck(:slug)).to match_array(%w[ps5 steam])
    end

    it "drops blank entries in the array silently" do
      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ "", ps5.id.to_s ]
      }
      expect(response).to redirect_to(game_path(game))
      expect(game.reload.owned_platforms.pluck(:slug)).to eq([ "ps5" ])
    end
  end

  # ------------------------------------------------------------
  # PATCH — sad / boundary
  # ------------------------------------------------------------

  describe "PATCH /games/:slug/platform_ownerships — sad / boundary" do
    it "rejects an unknown platform_id" do
      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ "999999" ]
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("unknown platform")
    end

    it "404s for an unknown game slug" do
      patch "/games/no-such-game/platform_ownerships"
      expect(response).to have_http_status(:not_found)
    end

    it "doesn't create rows when the submit is rejected" do
      expect {
        patch game_platform_ownerships_path(game), params: {
          platform_owned_ids: [ "999999" ]
        }
      }.not_to change(GamePlatformOwnership, :count)
    end

    it "de-duplicates id values silently (idempotent intent)" do
      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ ps5.id.to_s, ps5.id.to_s ]
      }
      expect(response).to redirect_to(game_path(game))
      expect(game.reload.game_platform_ownerships.where(platform: ps5).count).to eq(1)
    end
  end

  # ------------------------------------------------------------
  # Mass-assignment guard — only the ownership join is touched.
  # ------------------------------------------------------------

  describe "PATCH — mass-assignment guard" do
    it "silently drops smuggled Game attributes (e.g. title, notes)" do
      original_title = game.title
      original_notes = game.notes
      patch game_platform_ownerships_path(game), params: {
        game: { title: "EVIL", notes: "EVIL", igdb_id: 999 },
        platform_owned_ids: [ ps5.id.to_s ]
      }
      game.reload
      expect(game.title).to eq(original_title)
      expect(game.notes).to eq(original_notes)
    end

    it "silently drops smuggled IGDB-sourced attributes" do
      original_summary = game.summary
      patch game_platform_ownerships_path(game), params: {
        game: { summary: "EVIL" },
        platform_owned_ids: [ ps5.id.to_s ]
      }
      expect(game.reload.summary).to eq(original_summary)
    end
  end

  # ------------------------------------------------------------
  # Round-trip — second PATCH un-ticks PS5, keeps Steam.
  # ------------------------------------------------------------

  describe "PATCH — round-trip" do
    it "tick PS5+Steam then un-tick PS5 leaves Steam owned" do
      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ ps5.id.to_s, steam.id.to_s ]
      }
      ps5_row = game.game_platform_ownerships.find_by(platform: ps5)
      steam_row = game.game_platform_ownerships.find_by(platform: steam)
      expect(ps5_row).to be_present
      expect(steam_row).to be_present

      patch game_platform_ownerships_path(game), params: {
        platform_owned_ids: [ steam.id.to_s ]
      }
      expect(game.reload.owned_platforms.pluck(:slug)).to eq([ "steam" ])
    end
  end
end
