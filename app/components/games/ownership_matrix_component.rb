# 2026-05-17 BP slice (item 7 of the 10-item /games/:id reshape list)
# — per-platform ownership matrix rendered in the LEFT-pane
# `<section class="ownership">` block on `/games/:id`. Replaces the
# previous flat `platforms` / `played` / `footage` rows with one row
# per applicable platform (PS / Switch / Steam), each carrying:
#
#   `[owned]`  — `StatusBadgeComponent` (kind: :success, bordered green).
#                Rendered when the user owns the game on that platform
#                (`game.owned_platforms.include?(platform)`). Multiple
#                rows can carry `[owned]` (boolean per platform).
#
#   `[played]` — `StatusBadgeComponent` (kind: :strong, filled green).
#                Rendered ONLY on the row matching
#                `game.played_platform`. At most ONE row across the
#                matrix can carry `[played]` (singular constraint:
#                "I can choose only 1 platform for played").
#
# A row with neither chip renders a muted em-dash so the matrix shape
# stays legible (3 rows always present, state per row varies).
#
# The 3 platform slugs are pulled from `Platforms::ChipComponent::SLUG_BRAND`
# (canonical brand list) and intersected with `game_detail_logo_slugs`
# (the same applicable-slug filter the previous ownership block used)
# so the matrix only surfaces platforms IGDB lists the game on. Games
# with no applicable platforms fall back to a single em-dash row.
#
# Read-only display surface — no form, no submit. The editable surface
# stays on `/games/:id/edit` and the existing
# `Games::PlatformOwnershipsController` (per-platform toggle endpoint)
# / future `played_platform` editor. The `footage` row from the
# previous block is REMOVED from the UI here (BP slice scope: drop
# footage from ownership), but the underlying `Game#footage_*`
# columns are intact and will be consumed by the BQ TTB fuel-gauge
# footage tick.
module Games
  class OwnershipMatrixComponent < ViewComponent::Base
    include PlatformLogosHelper

    def initialize(game:)
      @game = game
    end

    attr_reader :game

    # Applicable platform slugs for this game — the full canonical
    # brand list (PS / Switch / Steam). The matrix ALWAYS renders all
    # three rows regardless of `game_detail_logo_slugs` (IGDB-reported
    # applicable set), so the user can mark ownership on any platform
    # — IGDB is incomplete for Switch ports / late-port titles and
    # the matrix must not gate on it. The user's manual ownership
    # toggle is the source of truth for the ownership matrix; IGDB's
    # `platforms_available` only drives the read-only chip surface
    # elsewhere on the page.
    def applicable_slugs
      Platforms::ChipComponent::SLUG_BRAND.keys
    end

    def platform_for(slug)
      platforms_by_slug[slug]
    end

    def owned?(slug)
      platform = platform_for(slug)
      return false unless platform

      owned_platform_ids.include?(platform.id)
    end

    def played?(slug)
      platform = platform_for(slug)
      return false unless platform
      return false unless game.played_platform_id

      game.played_platform_id == platform.id
    end

    def platform_label(slug)
      Platforms::ChipComponent::SLUG_BRAND.dig(slug, :label) || slug.to_s.upcase
    end

    private

    def platforms_by_slug
      @platforms_by_slug ||= Platform
        .where(slug: Platforms::ChipComponent::SLUG_BRAND.keys)
        .index_by(&:slug)
    end

    def owned_platform_ids
      @owned_platform_ids ||= game.game_platform_ownerships.pluck(:platform_id)
    end
  end
end
