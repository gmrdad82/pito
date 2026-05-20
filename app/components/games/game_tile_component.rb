# 2026-05-17 (Wave B6 VC) — rich game tile, ViewComponent edition.
#
# Extracted verbatim from `app/views/games/_tile.html.erb`. The partial
# accumulated logic across many waves (Phase 14 §3 → Phase 27 metadata
# refresh → Phase 28 §01a editions → Wave B3b chip overlay → Wave B6
# title-tooltip controller). This component is the single canonical
# implementation; the partial stays in place until the VC5 wiring
# dispatch swaps callers.
#
# Variants:
#   :grid   default — `/games` all-games grid, `/bundles/:id` grid.
#           Caption font 11px, meta font 10px.
#   :shelf  horizontally scrolling shelf rows on `/games`. Caption
#           font 10px, meta font 9px. Cover slot itself stays
#           150 × 200 px in both variants (the surrounding container
#           sizes the slot); only the caption typography shrinks. The
#           dedicated smaller cover artwork lives in
#           `Games::CoverComponent(variant: :shelf)` — a different
#           call shape consumed by the shelves-by-letter display
#           directly, NOT by this rich tile.
#
# All helpers are sourced from `helpers.<name>` so the component picks
# up the existing helper / url-helper surface without re-implementing
# anything. Methods that the partial inlined as Ruby expressions
# (chip-slug union, "not released" predicate, font sizing) live here
# as private methods to keep the template readable.
module Games
  class GameTileComponent < ViewComponent::Base
    VARIANTS = %i[grid shelf].freeze

    def initialize(game:, variant: :grid)
      @game = game
      @variant = variant.to_sym

      unless VARIANTS.include?(@variant)
        raise ArgumentError,
              "Unknown variant #{variant.inspect} (expected one of #{VARIANTS.inspect})"
      end
    end

    private

    attr_reader :game, :variant

    # 2026-05-11 polish (Fix 6) — a game is "not yet released" when its
    # `release_date` is nil OR in the future. The title renders bold via
    # the `.not-released` class so the workspace surfaces upcoming
    # entries at a glance.
    def not_released?
      game.release_date.blank? || game.release_date > Date.current
    end

    # Variant-keyed caption typography. Matches the values inlined in the
    # original partial verbatim.
    def caption_font_size
      variant == :shelf ? "10px" : "11px"
    end

    def meta_font_size
      variant == :shelf ? "9px" : "10px"
    end

    # 2026-05-17 (Wave B3b) — chips render in a `.tile-cover-chip-
    # overlay` on the cover's bottom-right corner. The set is the
    # owned ∪ available union, walked in `KNOWN_CHIPS` declaration
    # order so render stays deterministic across calls.
    def tile_chip_slugs
      detail_slugs = helpers.game_detail_chip_slugs(game)
      owned_pick   = helpers.game_index_tile_chip_slug(game)
      combined     = (detail_slugs + Array(owned_pick)).to_set

      PlatformChipsHelper::KNOWN_CHIPS.select { |slug| combined.include?(slug) }
    end

    # Phase 28 §01a — when an edition tile is rendered in flat mode
    # (`?include_editions=yes`), show a muted parent pointer above the
    # title so the user can navigate up to the primary. Returns the
    # parent record (truthy) or nil so the template can branch.
    def parent_pointer
      return nil unless game.edition?
      game.version_parent
    end

    def show_editions_badge?
      game.primary?
    end

    def game_path
      helpers.game_path(game)
    end
  end
end
