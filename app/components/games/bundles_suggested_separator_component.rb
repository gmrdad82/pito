module Games
  # 2026-05-19 — Cover-art-style separator tile that sits between the
  # "in bundles" (LEFT) and "suggested bundles" (RIGHT) halves of the
  # `/games/:id` bundles section.
  #
  # Replaces the vertical hairline divider
  # (`.bundles-section-divider`) the section used to render between the
  # two halves. The separator is now a tile-shaped marker matching the
  # bundle cover dimensions used in this shelf (150 × 200 — `:grid`
  # parity with `Games::BundleTileComponent`), so the row reads as one
  # uninterrupted strip of covers with the chevron tile cueing the
  # transition into recommendations.
  #
  # Markup contract for the consuming CSS rule
  # `.game-bundles .shelf-row:has(.bundles-suggested-separator:first-child) { gap: 0; }`:
  # the outer element MUST carry the `.bundles-suggested-separator`
  # class so the no-left-gap edge case (newly-added game with zero
  # in-bundles, separator becomes the first child of the shelf) can be
  # detected from CSS without a per-state modifier class plumbed from
  # the section component.
  #
  # Visual style mirrors the dashed-border, muted-copy placeholder
  # pattern already used by `.shelf-empty-tile` — same border, same
  # background, same muted text color — but sized to the grid bundle
  # cover (150 × 200) instead of the bare shelf cover (98 × 130) so it
  # reads as part of the bundle row rather than the "empty shelf"
  # branch.
  class BundlesSuggestedSeparatorComponent < ViewComponent::Base
    # 2026-05-19 — Two-column tile layout. LEFT column stacks the label
    # over two rows ("suggested" / "bundles"); RIGHT column is a tight
    # cluster of chevrons cueing the transition into the suggested half.
    # The chevron run is a single text node (one `>` repeated) so the
    # column stays a single inline-block flex child.
    LABEL_ROW_1 = "suggested".freeze
    LABEL_ROW_2 = "bundles".freeze
    CHEVRONS = ">>>".freeze

    def label_row_1
      LABEL_ROW_1
    end

    def label_row_2
      LABEL_ROW_2
    end

    def chevrons
      CHEVRONS
    end
  end
end
