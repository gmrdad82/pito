# 2026-05-17 — inline per-platform ownership matrix toggles for
# `/games/:id`. Powers the auto-submit checkbox cells rendered by
# `Games::OwnershipMatrixComponent`. Two actions:
#
#   PATCH /games/:game_id/ownership_toggles/:platform  → ownership
#   PATCH /games/:game_id/played_toggles/:platform     → played
#
# `:platform` is the chip slug (`ps` / `switch` / `steam`) from
# `Platforms::ChipComponent::SLUG_BRAND`. The router-side allowlist
# is reapplied here as defense-in-depth. The chip slug resolves to
# a canonical `Platform` row via
# `Platforms::ChipComponent::CANONICAL_PLATFORM_SLUG_BY_CHIP`
# (`ps` → `ps5`, `switch` → `switch-2`, `steam` → `steam`).
#
# 2026-05-18 FN2 — `ownership=yes` ALSO upserts a `game_platforms`
# join row (`platforms_available`) with `source: "user"` when IGDB
# has not listed the platform yet, so the chip-availability surfaces
# (`/games` shelf chips, `?filters=ps|switch|steam` filter, the
# detail-page platform chip strip) all light up. `ownership=no`
# tears down the user-added row but leaves any IGDB-sourced row
# alone (un-marking ownership never erases IGDB's release knowledge).
#
# `ownership` flips the `game_platform_ownerships` join for the
# `(game, platform)` pair — destroy when present, create when absent.
# Multi-select per game (a single game can be owned on multiple
# platforms simultaneously).
#
# `played` flips the singular `played_platform_id` pointer — set to
# the chosen platform if currently nil OR pointed at a different
# platform; set to nil if currently pointed at the chosen platform
# (toggle-off). At most one platform is "played" at any time.
#
# Body shape: `enabled=yes|no` per the yes/no boundary rule. The
# value names the DESIRED end state from the checkbox flip (a freshly
# checked box posts `enabled=yes`; an unchecked box submits nothing,
# which `coerce_boolean` treats as `enabled=no`). The controller still
# diffs current vs desired before mutating so a stale POST against
# already-current state is idempotent.
#
# Response: redirect back to `/games/:id` with a flash naming the
# new state — Turbo follows the redirect, the page re-renders with
# the matrix reflecting the persisted state, and the flash toast
# surfaces via the layout-level `_flash_toasts.html.erb` region
# (top-layer popover so it sits above any open modal).
module Games
  class OwnershipTogglesController < ApplicationController
    PLATFORM_SLUGS = Platforms::ChipComponent::SLUG_BRAND.keys.freeze

    before_action :load_game
    before_action :load_platform

    def ownership
      desired = coerce_boolean(:enabled)
      currently_owned = @game.game_platform_ownerships.exists?(platform_id: @platform.id)

      if desired && !currently_owned
        @game.game_platform_ownerships.create!(platform_id: @platform.id)

        # 2026-05-18 FN2 — when the user marks the game as owned on a
        # platform IGDB did not list (`platforms_available` does not
        # already contain `@platform`), insert a `game_platforms` join
        # row with `source: "user"` so the chip-availability surfaces
        # (`/games` shelf chips, `?filters=ps|switch|steam` filter,
        # detail-page platform chips) all light up. The `source` tag
        # preserves the user-added origin so a later IGDB sync (FN3)
        # does not silently drop the row.
        ensure_user_added_platform_availability!

        redirect_to game_path(@game),
                    notice: "Game owned on #{platform_label}."
      elsif !desired && currently_owned
        @game.game_platform_ownerships.where(platform_id: @platform.id).destroy_all

        # 2026-05-18 cascade — if the un-owned platform was the
        # singular `played_platform`, clear the pointer too. You
        # cannot "be playing on" a platform you no longer own; the
        # client-side Stimulus cascade already unticks the played
        # checkbox in the same flow, but JS-disabled clients +
        # racing requests still converge here.
        if @game.played_platform_id == @platform.id
          @game.update!(played_platform_id: nil)
        end

        # 2026-05-18 FN2 — drop the matching `game_platforms` row
        # only when it was user-added (`source: "user"`). IGDB-sourced
        # rows stay alone: un-marking ownership does not erase IGDB's
        # knowledge that the game ships on that platform.
        @game.game_platforms
             .where(platform_id: @platform.id, source: "user")
             .destroy_all

        redirect_to game_path(@game),
                    notice: "Game no longer owned on #{platform_label}."
      else
        # No-op (state already matches desired). Re-render with no
        # flash so a duplicate / racing POST does not stack a misleading
        # toast.
        redirect_to game_path(@game)
      end
    end

    def played
      desired = coerce_boolean(:enabled)
      currently_played = @game.played_platform_id == @platform.id

      if desired && !currently_played
        # 2026-05-18 cascade — a "played" platform must also be
        # "owned". Auto-create the ownership join if it doesn't
        # already exist, then point `played_platform_id` at this
        # platform. The Stimulus cascade controller ticks the
        # `owned` checkbox client-side and submits its own form,
        # but the server still enforces the invariant so racing
        # requests + JS-disabled clients land on the same state.
        unless @game.game_platform_ownerships.exists?(platform_id: @platform.id)
          @game.game_platform_ownerships.create!(platform_id: @platform.id)
        end
        # 2026-05-18 FN2 cascade — mirror the `ownership` action's
        # availability backfill. A platform the user is actively
        # playing on must be available; if IGDB has not listed it,
        # tag the join row `source: "user"` so FN3 preserves it.
        ensure_user_added_platform_availability!
        @game.update!(played_platform_id: @platform.id)
        redirect_to game_path(@game),
                    notice: "Playing on #{platform_label}."
      elsif !desired && currently_played
        @game.update!(played_platform_id: nil)
        redirect_to game_path(@game),
                    notice: "No longer playing on #{platform_label}."
      else
        # No-op (state already matches desired). Same idempotent posture
        # as `ownership` above.
        redirect_to game_path(@game)
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to game_path(@game),
                  alert: e.record.errors.full_messages.to_sentence.presence ||
                         "could not update played platform."
    end

    private

    def load_game
      @game = Game.friendly.find(params[:game_id])
    end

    def load_platform
      slug = params[:platform].to_s
      unless PLATFORM_SLUGS.include?(slug)
        redirect_to game_path(@game), alert: "unknown platform."
        return
      end

      # 2026-05-18 FN2 — chip slug → canonical Platform slug. The chip
      # vocabulary (`ps` / `switch` / `steam`) collapses multiple IGDB
      # platforms into one user-facing surface; the actual Platform
      # row is keyed by its FriendlyId slug (`ps5`, `switch-2`, `steam`)
      # per `Platforms::ChipComponent::CANONICAL_PLATFORM_SLUG_BY_CHIP`.
      canonical_slug = Platforms::ChipComponent::CANONICAL_PLATFORM_SLUG_BY_CHIP[slug]
      @platform = Platform.find_by(slug: canonical_slug)
      unless @platform
        redirect_to game_path(@game), alert: "unknown platform."
        nil
      end
    end

    # 2026-05-18 FN2 — idempotent upsert of the `game_platforms` join
    # row for the canonical `@platform`. Tags the row `source: "user"`
    # so the IGDB sync (FN3) can preserve user-added platforms across
    # subsequent syncs. If a row already exists (e.g. IGDB had already
    # added the platform), leaves its `source` alone — the row's
    # provenance keeps the earlier value (conflict rule: first writer
    # wins, never downgrade `user` to `igdb`).
    def ensure_user_added_platform_availability!
      return if @game.game_platforms.exists?(platform_id: @platform.id)

      @game.game_platforms.create!(platform_id: @platform.id, source: "user")
    end

    def coerce_boolean(key)
      raw = params[key].to_s
      YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
    end

    # 2026-05-18 FN2 — flash labels stay in the chip vocabulary
    # (`PS` / `Switch` / `Steam`), NOT the canonical Platform slug
    # (`ps5` / `switch2` / `steam`). Look up via the inbound chip slug
    # from `params[:platform]` so the toast copy matches the chip the
    # user clicked.
    def platform_label
      chip_slug = params[:platform].to_s
      Platforms::ChipComponent::SLUG_BRAND.dig(chip_slug, :label) ||
        chip_slug.upcase
    end
  end
end
