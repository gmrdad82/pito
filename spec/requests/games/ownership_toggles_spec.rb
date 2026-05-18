require "rails_helper"

# 2026-05-18 — `Games::OwnershipTogglesController` request specs.
#
# Endpoints (per `config/routes.rb` lines 287-292):
#   PATCH /games/:game_id/ownership_toggles/:platform → #ownership
#   PATCH /games/:game_id/played_toggles/:platform    → #played
#
# `:platform` is the chip slug (`ps` / `switch` / `steam`) from
# `Platforms::ChipComponent::SLUG_BRAND`. The controller resolves the
# chip slug to a canonical `Platform` row via
# `CANONICAL_PLATFORM_SLUG_BY_CHIP` (`ps` → `ps5`, `switch` →
# `switch-2`, `steam` → `steam`).
#
# Body shape uses the yes/no boundary rule — `enabled=yes|no` per
# `YesNo.from_yes_no`. A freshly checked box posts `enabled=yes`; an
# unchecked box submits nothing, which the controller treats as `no`.
#
# FN2 — when the user marks ownership / played on a platform IGDB has
# not listed yet, the controller upserts a `game_platforms` join row
# with `source: "user"` so the chip-availability surfaces light up.
# Un-marking ownership tears down the user-source row but leaves any
# IGDB-source row alone.
RSpec.describe "Games::OwnershipToggles", type: :request do
  # Friendly slug build helper — Platform's FriendlyId derives the slug
  # from `name`. The chip-to-canonical map expects exact slugs (`ps5`,
  # `switch-2`, `steam`), so we override the slug after create.
  def make_platform(name:, slug:, igdb_id: nil)
    p = Platform.create!(name: name, igdb_id: igdb_id || rand(10_000..99_999))
    p.update_column(:slug, slug)
    p
  end

  let!(:game) { create(:game, :synced, title: "Test Game", igdb_slug: "test-game") }
  let!(:ps5_platform)     { make_platform(name: "PlayStation 5",     slug: "ps5",      igdb_id: 167) }
  let!(:switch2_platform) { make_platform(name: "Nintendo Switch 2", slug: "switch-2", igdb_id: 508) }
  let!(:steam_platform)   { make_platform(name: "Steam",             slug: "steam",    igdb_id: 6) }

  # ----------------------------------------------------------------
  # #ownership — chip slug resolution + happy path.
  # ----------------------------------------------------------------

  describe "PATCH /games/:game_id/ownership_toggles/:platform" do
    it "maps chip `ps` → canonical PS5 platform when creating ownership" do
      expect {
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "yes" }
      }.to change { game.reload.game_platform_ownerships.count }.from(0).to(1)

      expect(game.game_platform_ownerships.first.platform_id).to eq(ps5_platform.id)
      expect(response).to redirect_to(game_path(game))
    end

    it "maps chip `switch` → canonical switch-2 platform when creating ownership" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "switch"),
            params: { enabled: "yes" }
      expect(game.reload.game_platform_ownerships.first.platform_id).to eq(switch2_platform.id)
    end

    it "maps chip `steam` → canonical steam platform when creating ownership" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "steam"),
            params: { enabled: "yes" }
      expect(game.reload.game_platform_ownerships.first.platform_id).to eq(steam_platform.id)
    end

    it "flashes the per-chip label on owned (`PS`)" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(flash[:notice]).to eq("Game owned on PS.")
    end

    # ------------------------------------------------------------
    # FN2 — `game_platforms` availability backfill.
    # ------------------------------------------------------------

    describe "FN2 availability backfill" do
      it "creates a game_platforms row with source `user` when IGDB has not listed the platform" do
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "yes" }
        }.to change { game.reload.game_platforms.where(platform_id: ps5_platform.id).count }.from(0).to(1)

        row = game.game_platforms.find_by(platform_id: ps5_platform.id)
        expect(row.source).to eq("user")
      end

      it "does NOT downgrade an existing IGDB-source row" do
        game.game_platforms.create!(platform: ps5_platform, source: "igdb")
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "yes" }
        row = game.reload.game_platforms.find_by(platform_id: ps5_platform.id)
        expect(row.source).to eq("igdb")
      end

      it "does not create a duplicate game_platforms row when one already exists (any source)" do
        game.game_platforms.create!(platform: ps5_platform, source: "user")
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "yes" }
        }.not_to change { game.reload.game_platforms.where(platform_id: ps5_platform.id).count }
      end
    end

    # ------------------------------------------------------------
    # Un-owning — destroys the ownership row + the user-source
    # availability row, but leaves IGDB-source availability alone.
    # ------------------------------------------------------------

    describe "un-owning (enabled=no)" do
      before do
        game.game_platform_ownerships.create!(platform: ps5_platform)
        game.game_platforms.create!(platform: ps5_platform, source: "user")
      end

      it "destroys the ownership row" do
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "no" }
        }.to change { game.reload.game_platform_ownerships.count }.from(1).to(0)
      end

      it "destroys the user-source game_platforms row" do
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "no" }
        }.to change { game.reload.game_platforms.where(platform_id: ps5_platform.id).count }.from(1).to(0)
      end

      it "preserves an IGDB-source game_platforms row on the same platform" do
        # Replace the user-source row with an IGDB-source row.
        game.game_platforms.where(platform_id: ps5_platform.id).destroy_all
        game.game_platforms.create!(platform: ps5_platform, source: "igdb")

        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "no" }
        expect(game.reload.game_platforms.where(platform_id: ps5_platform.id, source: "igdb")).to exist
      end

      it "flashes `no longer owned` with the chip label" do
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "no" }
        expect(flash[:notice]).to eq("Game no longer owned on PS.")
      end

      it "clears the played_platform_id pointer when the un-owned platform was the played one" do
        game.update!(played_platform_id: ps5_platform.id)
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "no" }
        expect(game.reload.played_platform_id).to be_nil
      end

      it "leaves an unrelated played_platform_id alone when un-owning a different platform" do
        game.game_platform_ownerships.create!(platform: switch2_platform)
        game.update!(played_platform_id: switch2_platform.id)
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "no" }
        expect(game.reload.played_platform_id).to eq(switch2_platform.id)
      end
    end

    # ------------------------------------------------------------
    # Idempotency — no-op when state already matches desired.
    # ------------------------------------------------------------

    describe "idempotent re-submit" do
      it "is a no-op when already owned and submits enabled=yes (no flash)" do
        game.game_platform_ownerships.create!(platform: ps5_platform)
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "yes" }
        }.not_to change { game.reload.game_platform_ownerships.count }
        expect(flash[:notice]).to be_nil
      end

      it "is a no-op when not owned and submits enabled=no (no flash)" do
        expect {
          patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
                params: { enabled: "no" }
        }.not_to change { game.reload.game_platform_ownerships.count }
        expect(flash[:notice]).to be_nil
      end
    end
  end

  # ----------------------------------------------------------------
  # #played — cascade: clicking played auto-owns and is the singular
  # played_platform_id pointer.
  # ----------------------------------------------------------------

  describe "PATCH /games/:game_id/played_toggles/:platform" do
    it "sets played_platform_id when not yet played" do
      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(game.reload.played_platform_id).to eq(ps5_platform.id)
    end

    it "auto-creates the ownership row if missing (played → owned cascade)" do
      expect {
        patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
              params: { enabled: "yes" }
      }.to change { game.reload.game_platform_ownerships.where(platform_id: ps5_platform.id).count }.from(0).to(1)
    end

    it "FN2 — backfills a user-source game_platforms row when IGDB has not listed the platform" do
      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      row = game.reload.game_platforms.find_by(platform_id: ps5_platform.id)
      expect(row).not_to be_nil
      expect(row.source).to eq("user")
    end

    it "preserves an existing IGDB-source availability row when marking played" do
      game.game_platforms.create!(platform: ps5_platform, source: "igdb")
      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(game.reload.game_platforms.find_by(platform_id: ps5_platform.id).source).to eq("igdb")
    end

    it "flashes `playing_on` with the chip label" do
      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(flash[:notice]).to eq("Playing on PS.")
    end

    it "is singular — switching played to a different platform replaces the pointer" do
      game.game_platform_ownerships.create!(platform: ps5_platform)
      game.update!(played_platform_id: ps5_platform.id)

      patch game_played_toggle_path(game_id: game.to_param, platform: "switch"),
            params: { enabled: "yes" }
      expect(game.reload.played_platform_id).to eq(switch2_platform.id)
    end

    it "clears the pointer when un-checking the currently played platform" do
      game.game_platform_ownerships.create!(platform: ps5_platform)
      game.update!(played_platform_id: ps5_platform.id)

      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "no" }
      expect(game.reload.played_platform_id).to be_nil
    end

    it "flashes `no_longer_playing` when un-checking the played platform" do
      game.game_platform_ownerships.create!(platform: ps5_platform)
      game.update!(played_platform_id: ps5_platform.id)

      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "no" }
      expect(flash[:notice]).to eq("No longer playing on PS.")
    end

    it "is a no-op when not playing on this platform and submits enabled=no" do
      # No flash on idempotent no-op — controller falls through to the
      # plain `redirect_to` branch.
      patch game_played_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "no" }
      expect(game.reload.played_platform_id).to be_nil
      expect(flash[:notice]).to be_nil
    end
  end

  # ----------------------------------------------------------------
  # Unknown platform handling — defensive checks on the controller's
  # allowlist + Platform-row resolution.
  # ----------------------------------------------------------------

  describe "unknown platform handling" do
    it "flashes `unknown platform.` for a slug outside the chip allowlist (ownership)" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "xbox"),
            params: { enabled: "yes" }
      expect(response).to redirect_to(game_path(game))
      expect(flash[:alert]).to eq("unknown platform.")
    end

    it "flashes `unknown platform.` for a slug outside the chip allowlist (played)" do
      patch game_played_toggle_path(game_id: game.to_param, platform: "xbox"),
            params: { enabled: "yes" }
      expect(flash[:alert]).to eq("unknown platform.")
    end

    it "does not mutate state when the chip slug is unknown" do
      expect {
        patch game_ownership_toggle_path(game_id: game.to_param, platform: "xbox"),
              params: { enabled: "yes" }
      }.not_to change(GamePlatformOwnership, :count)
    end

    it "flashes `unknown platform.` when the canonical Platform row does not exist" do
      ps5_platform.destroy!
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(flash[:alert]).to eq("unknown platform.")
    end
  end

  # ----------------------------------------------------------------
  # Routing edge cases.
  # ----------------------------------------------------------------

  describe "routing edge cases" do
    it "resolves the game by its friendly slug" do
      patch "/games/test-game/ownership_toggles/ps", params: { enabled: "yes" }
      expect(response).to redirect_to(game_path(game))
    end

    it "404s for an unknown game slug" do
      patch "/games/no-such-game/ownership_toggles/ps", params: { enabled: "yes" }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ----------------------------------------------------------------
  # Yes/no boundary — strict per CLAUDE.md hard rule.
  # ----------------------------------------------------------------

  describe "yes/no boundary" do
    it "treats `yes` as enable" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "yes" }
      expect(game.reload.game_platform_ownerships.count).to eq(1)
    end

    it "treats `no` as disable" do
      game.game_platform_ownerships.create!(platform: ps5_platform)
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "no" }
      expect(game.reload.game_platform_ownerships.count).to eq(0)
    end

    it "treats missing param (unchecked box) as `no`" do
      game.game_platform_ownerships.create!(platform: ps5_platform)
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps")
      expect(game.reload.game_platform_ownerships.count).to eq(0)
    end

    it "ignores non-yes/no values (treated as `no` — strict boundary)" do
      patch game_ownership_toggle_path(game_id: game.to_param, platform: "ps"),
            params: { enabled: "true" }
      expect(game.reload.game_platform_ownerships.count).to eq(0)
    end
  end
end
