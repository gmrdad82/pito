# Phase 27 Wave F (2026-05-17) — Bundle shelf tile, extracted from
# `app/views/games/_bundle_for_shelf_tile.html.erb` into a
# ViewComponent. The partial remains in place; this component
# duplicates its render so the wiring swap (VC5) can happen as a
# follow-up dispatch without coupling extraction + wiring into one
# change.
#
# Renders one bundle in the `/games` Bundles outer shelf row at
# 150 × 200 (letter-shelf parity). Shows the composite cover when
# `BundleCoverBuild` has produced one; otherwise falls back to the
# project's theme-aware grid SVGs. When the bundle holds more than
# nine members, an HTML `+N` overlay (via `StatusBadgeComponent
# kind: :neutral`) is rendered flush to the cover's bottom-right
# corner — counting strictly the members HIDDEN behind the 9-grid
# composite (so a 10-member bundle reads `+1`).
#
# Click target is unchanged from the partial: a Stimulus action on
# the wrapping `<a>` opens the layout-level `<dialog
# id="bundles-modal">` and points its Turbo Frame `src` at
# `/bundles/<id>/games_pane`. The href fallback (`/bundles/<slug>`)
# keeps the link meaningful for JS-off users and screen readers.
#
# 2026-05-18 — `size:` + `mode:` extension for the /games/:id bundles
# section:
#   * `size: :grid` (default) — 150 × 200 composite with caption beneath
#     (existing /games shelf treatment).
#   * `size: :shelf` — 98 × 130 bare composite, no caption (genre-shelf
#     parity for the /games/:id row of "bundles this game is in" and
#     "suggested bundles").
#   * `mode: :default` (existing) — anchor opens the layout-level
#     bundles modal.
#   * `mode: :suggest` — button_to POST `/bundles/:id/members?game_id=…`
#     so clicking adds the supplied `target_game:` to the bundle. Used
#     by the right-half of the /games/:id bundles section.
class Game
  class BundleTileComponent < ViewComponent::Base
    SIZES = {
      grid:  { width: 150, height: 200, fallback_variant: "grid",  show_caption: true },
      shelf: { width: 98,  height: 130, fallback_variant: "shelf", show_caption: false }
    }.freeze

    def initialize(bundle:, size: :grid, mode: :default, target_game: nil)
      @bundle = bundle
      @size = size.to_sym
      unless SIZES.key?(@size)
        raise ArgumentError,
              "Unknown bundle tile size #{size.inspect} (expected one of #{SIZES.keys.inspect})"
      end
      @mode = mode.to_sym
      unless %i[default suggest].include?(@mode)
        raise ArgumentError,
              "Unknown bundle tile mode #{mode.inspect} (expected :default or :suggest)"
      end
      if @mode == :suggest && target_game.nil?
        raise ArgumentError, "bundle tile mode :suggest requires target_game:"
      end
      @target_game = target_game
      @dims = SIZES.fetch(@size)
    end

    private

    attr_reader :bundle, :size, :mode, :target_game

    def width
      @dims[:width]
    end

    def height
      @dims[:height]
    end

    def fallback_variant
      @dims[:fallback_variant]
    end

    def show_caption?
      @dims[:show_caption]
    end

    def suggest_mode?
      @mode == :suggest
    end

    # Number of bundle members HIDDEN behind the 9-grid composite.
    # A 10-member bundle reads `+1`, an 11-member bundle reads `+2`,
    # etc. Negative / zero values mean the bundle fits inside the
    # 9-cell grid and no overlay is rendered.
    def overflow_n
      bundle.bundle_members.size - 9
    end

    def has_overflow?
      overflow_n > 0
    end

    def composite_url
      bundle.composite_cover_url
    end

    # Slug-aware identifier — mirrors the partial's local-var
    # fallback (slug when present, id.to_s otherwise) so URLs survive
    # bundles created before slugs were backfilled.
    def bundle_slug
      bundle.respond_to?(:slug) && bundle.slug.present? ? bundle.slug : bundle.id.to_s
    end

    def pane_url
      helpers.games_pane_bundle_path(bundle_slug)
    end

    def fallback_href
      helpers.bundle_path(bundle_slug)
    end

    # PATCH endpoint the bundles modal's inline title edit submits
    # against. The modal trigger writes this onto the
    # `inline-title-edit` controller's `urlValue` so a save targets
    # the currently-opened bundle.
    def update_url
      helpers.bundle_path(bundle_slug)
    end

    # 2026-05-18 — DOM id of the per-bundle delete-confirm `<dialog>`
    # rendered as a sibling in `_bundles_for_shelf`. The bundles-modal
    # trigger writes this value onto the modal's `[-]` button so it
    # opens the matching dialog for the currently-opened bundle.
    def delete_confirm_id
      "confirm_delete_bundle_#{bundle.id}"
    end

    # POST endpoint for `mode: :suggest`. Adds the supplied
    # `target_game:` to this bundle. The controller branches on the
    # `source` param so the post-create redirect lands back on
    # /games/:id (vs the steady-state bundle_path redirect).
    def add_member_url
      helpers.bundle_members_path(bundle_slug)
    end

    def aria_label
      suggest_mode? ? I18n.t("bundles.tile.add_aria", bundle: bundle.name) : bundle.name
    end
  end
end
