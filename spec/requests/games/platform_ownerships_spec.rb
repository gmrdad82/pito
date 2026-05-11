require "rails_helper"

# Phase 27 §01f — Per-platform ownership editor controller specs.
#
# Routes:
#
#   GET    /games/:game_id/platform_ownerships/edit  → edit
#   PATCH  /games/:game_id/platform_ownerships       → update
#
# The controller:
#   - Scaffolds in-memory rows for every IGDB release-platform.
#   - Accepts `_own: "yes"|"no"` per the project's yes/no boundary.
#   - On update: creates rows for ticked platforms, destroys rows for
#     un-ticked existing platforms, leaves un-ticked-and-not-existing
#     rows alone (no-op).
#   - 422s on invalid input (bad yes/no value, unknown platform,
#     duplicate platform).
RSpec.describe "Games::PlatformOwnerships", type: :request do
  let!(:game)  { create(:game, :synced, title: "Test", igdb_slug: "test-game") }
  let!(:ps5)   { create(:platform, name: "PS5",   slug: "ps5") }
  let!(:steam) { create(:platform, name: "Steam", slug: "steam") }
  let!(:gog)   { create(:platform, name: "GOG",   slug: "gog") }

  before do
    # All three platforms are in the IGDB release set; the user owns
    # none of them yet.
    game.platforms_available << ps5
    game.platforms_available << steam
    game.platforms_available << gog
  end

  # ------------------------------------------------------------
  # GET /games/:slug/platform_ownerships/edit
  # ------------------------------------------------------------

  describe "GET /games/:slug/platform_ownerships/edit" do
    it "returns 200" do
      get edit_game_platform_ownerships_path(game)
      expect(response).to have_http_status(:ok)
    end

    it "renders one fieldset row per release-platform" do
      get edit_game_platform_ownerships_path(game)
      expect(response.body.scan(/<fieldset class="platform-ownership-row"/).size).to eq(3)
    end

    it "renders rows alphabetical (case-insensitive)" do
      get edit_game_platform_ownerships_path(game)
      gog_idx   = response.body.index("data-platform-slug=\"gog\"")
      ps5_idx   = response.body.index("data-platform-slug=\"ps5\"")
      steam_idx = response.body.index("data-platform-slug=\"steam\"")
      expect([ gog_idx, ps5_idx, steam_idx ]).to eq([ gog_idx, ps5_idx, steam_idx ].sort)
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

    it "renders the '(no platforms available)' placeholder when the game has zero release-platforms" do
      lonely_game = create(:game, :synced, title: "Lonely", igdb_slug: "lonely")
      get edit_game_platform_ownerships_path(lonely_game)
      expect(response.body).to include("(no platforms available)")
    end
  end

  # ------------------------------------------------------------
  # PATCH /games/:slug/platform_ownerships — happy
  # ------------------------------------------------------------

  describe "PATCH /games/:slug/platform_ownerships — happy" do
    it "creates ownership rows for every ticked platform and redirects to show" do
      expect {
        patch game_platform_ownerships_path(game), params: {
          game: {
            game_platform_ownerships_attributes: {
              "0" => { platform_id: ps5.id,   _own: "yes" },
              "1" => { platform_id: steam.id, _own: "yes" },
              "2" => { platform_id: gog.id,   _own: "no" }
            }
          }
        }
      }.to change(GamePlatformOwnership, :count).by(2)

      expect(response).to redirect_to(game_path(game))
      expect(flash[:notice]).to include("ownership updated")
      expect(game.reload.owned_platforms.pluck(:slug)).to match_array(%w[ps5 steam])
    end

    it "destroys the row for an un-ticked existing platform" do
      create(:game_platform_ownership, game: game, platform: ps5)
      expect {
        patch game_platform_ownerships_path(game), params: {
          game: {
            game_platform_ownerships_attributes: {
              "0" => { id: game.game_platform_ownerships.find_by(platform: ps5).id,
                       platform_id: ps5.id, _own: "no" }
            }
          }
        }
      }.to change(GamePlatformOwnership, :count).by(-1)

      expect(game.reload.owned_platforms).to be_empty
    end

    it "keeps a row when its _own stays 'yes'" do
      existing = create(:game_platform_ownership, game: game, platform: ps5)
      expect {
        patch game_platform_ownerships_path(game), params: {
          game: {
            game_platform_ownerships_attributes: {
              "0" => { id: existing.id, platform_id: ps5.id, _own: "yes" }
            }
          }
        }
      }.not_to change(GamePlatformOwnership, :count)
    end

    it "persists acquired_at / store / notes on a new row" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => {
              platform_id: ps5.id,
              _own: "yes",
              acquired_at: "2024-03-15",
              store: "PSN",
              notes: "summer sale"
            }
          }
        }
      }
      row = game.game_platform_ownerships.find_by(platform: ps5)
      expect(row.acquired_at.to_date).to eq(Date.new(2024, 3, 15))
      expect(row.store).to eq("PSN")
      expect(row.notes).to eq("summer sale")
    end

    it "empty submit (every _own=no) un-owns everything" do
      create(:game_platform_ownership, game: game, platform: ps5)
      create(:game_platform_ownership, game: game, platform: steam)
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { id: game.game_platform_ownerships.find_by(platform: ps5).id,
                     platform_id: ps5.id, _own: "no" },
            "1" => { id: game.game_platform_ownerships.find_by(platform: steam).id,
                     platform_id: steam.id, _own: "no" }
          }
        }
      }
      expect(game.reload.owned_platforms).to be_empty
    end

    it "no-op when all platforms are un-ticked-and-not-existing" do
      expect {
        patch game_platform_ownerships_path(game), params: {
          game: {
            game_platform_ownerships_attributes: {
              "0" => { platform_id: ps5.id,   _own: "no" },
              "1" => { platform_id: steam.id, _own: "no" }
            }
          }
        }
      }.not_to change(GamePlatformOwnership, :count)
      expect(response).to redirect_to(game_path(game))
    end
  end

  # ------------------------------------------------------------
  # PATCH — sad / boundary
  # ------------------------------------------------------------

  describe "PATCH /games/:slug/platform_ownerships — sad / boundary" do
    it "rejects _own='true' (yes/no boundary)" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "true" }
          }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("_own must be").and include("yes").and include("no")
    end

    it "rejects _own='1' (yes/no boundary)" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "1" }
          }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects _own='false' (yes/no boundary)" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "false" }
          }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an unknown platform_id" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: 999_999, _own: "yes" }
          }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("unknown platform")
    end

    it "rejects a duplicate platform_id within the same submit" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "yes" },
            "1" => { platform_id: ps5.id, _own: "yes" }
          }
        }
      }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("duplicate")
    end

    it "404s for an unknown game slug" do
      patch "/games/no-such-game/platform_ownerships"
      expect(response).to have_http_status(:not_found)
    end

    it "doesn't create rows when the submit is rejected" do
      expect {
        patch game_platform_ownerships_path(game), params: {
          game: {
            game_platform_ownerships_attributes: {
              "0" => { platform_id: ps5.id, _own: "true" }
            }
          }
        }
      }.not_to change(GamePlatformOwnership, :count)
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
        game: {
          title: "EVIL",
          notes: "EVIL",
          igdb_id: 999,
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "yes" }
          }
        }
      }
      game.reload
      expect(game.title).to eq(original_title)
      expect(game.notes).to eq(original_notes)
    end

    it "silently drops smuggled IGDB-sourced attributes" do
      original_summary = game.summary
      patch game_platform_ownerships_path(game), params: {
        game: {
          summary: "EVIL",
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id, _own: "yes" }
          }
        }
      }
      expect(game.reload.summary).to eq(original_summary)
    end
  end

  # ------------------------------------------------------------
  # Flaw — stale id from a deleted-in-another-tab row.
  # ------------------------------------------------------------

  describe "PATCH — stale ownership id from another tab" do
    it "handles a stale id gracefully (no 500)" do
      existing = create(:game_platform_ownership, game: game, platform: ps5)
      # Simulate another tab destroying the row first.
      existing.destroy!
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { id: existing.id, platform_id: ps5.id, _own: "no" }
          }
        }
      }
      expect(response.status).to be_between(200, 499)
    end
  end

  # ------------------------------------------------------------
  # Round-trip — second PATCH un-ticks PS5, keeps Steam.
  # ------------------------------------------------------------

  describe "PATCH — round-trip" do
    it "tick PS5+Steam then un-tick PS5 leaves Steam owned" do
      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { platform_id: ps5.id,   _own: "yes" },
            "1" => { platform_id: steam.id, _own: "yes" }
          }
        }
      }
      ps5_row = game.game_platform_ownerships.find_by(platform: ps5)
      steam_row = game.game_platform_ownerships.find_by(platform: steam)
      expect(ps5_row).to be_present
      expect(steam_row).to be_present

      patch game_platform_ownerships_path(game), params: {
        game: {
          game_platform_ownerships_attributes: {
            "0" => { id: ps5_row.id,   platform_id: ps5.id,   _own: "no" },
            "1" => { id: steam_row.id, platform_id: steam.id, _own: "yes" }
          }
        }
      }
      expect(game.reload.owned_platforms.pluck(:slug)).to eq([ "steam" ])
    end
  end
end
