# 2026-05-18 — Bundles empty-cover netflix-3 placeholder primitive.
#
# Extracted from `app/views/bundles/games_pane.html.erb` (B6 of the
# `beta3-B-candidates` playbook). The block previously sat inline as
# the `else` branch of the populated-composite gate in the modal
# frame: a 3-cell netflix-style grid (one large main cell + two
# smaller stacked cells) where each cell embeds the shared game-
# cover fallback SVG (controller icon) at two sizes, with light +
# dark theme variants stacked and toggled via `[data-theme]` rules.
#
# Modifier:
# - `modifier: :modal` lifts the controller-icon max-width caps so
#   the SVGs scale proportionally at the bundles modal's larger
#   cover size. Default (`modifier: nil`) renders the shelf-tile
#   sized placeholder — same markup minus the `--modal` modifier on
#   the wrapper.
#
# Step 1 of the dedup: this component owns the modal placeholder.
# Step 2 (deferred) — swap the duplicated inline copy in
# `Games::BundleTileComponent` (both `suggest_mode?` and default
# branches) to render this component with `modifier: nil` so the
# shelf-tile no-cover fallback shares the same primitive.
module Bundles
  class EmptyCoverPlaceholderComponent < ViewComponent::Base
    # @param bundle [Bundle, nil] optional bundle used for the
    #   wrapper's `aria-label` / `title` text. Omit (or pass nil) for
    #   contexts where there is no specific bundle to name.
    # @param modifier [Symbol, nil] `:modal` for the bundles modal
    #   sizing; default (`nil`) for the shelf-tile sizing.
    def initialize(bundle: nil, modifier: nil)
      @bundle = bundle
      @modifier = modifier
    end

    attr_reader :bundle, :modifier

    def modal?
      modifier == :modal
    end

    def wrapper_classes
      base = "bundle-tile__nocover-netflix3"
      modal? ? "#{base} #{base}--modal" : base
    end

    def label
      bundle&.name.to_s
    end
  end
end
