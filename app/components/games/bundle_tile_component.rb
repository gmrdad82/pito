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
module Games
  class BundleTileComponent < ViewComponent::Base
    def initialize(bundle:)
      @bundle = bundle
    end

    private

    attr_reader :bundle

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
  end
end
