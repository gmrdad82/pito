# 2026-05-17 — inline per-platform ownership matrix toggles for
# `/games/:id`. Powers the auto-submit checkbox cells rendered by
# `Games::OwnershipMatrixComponent`. Two actions:
#
#   PATCH /games/:game_id/ownership_toggles/:platform  → ownership
#   PATCH /games/:game_id/played_toggles/:platform     → played
#
# `:platform` is the canonical slug (`ps` / `switch` / `steam`) from
# `Platforms::ChipComponent::SLUG_BRAND`. The router-side allowlist
# is reapplied here as defense-in-depth.
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
        redirect_to game_path(@game),
                    notice: "Game owned on #{platform_label}."
      elsif !desired && currently_owned
        @game.game_platform_ownerships.where(platform_id: @platform.id).destroy_all
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

      @platform = Platform.find_by(slug: slug)
      unless @platform
        redirect_to game_path(@game), alert: "unknown platform."
        nil
      end
    end

    def coerce_boolean(key)
      raw = params[key].to_s
      YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
    end

    def platform_label
      Platforms::ChipComponent::SLUG_BRAND.dig(@platform.slug, :label) ||
        @platform.slug.to_s.upcase
    end
  end
end
