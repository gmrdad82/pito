# 2026-05-18 — Bundle modal "all games" table: rating-score chip.
#
# Renders the canonical synthesized rating score for a `Game` as a
# small inline chip whose background color tracks the same seven-tier
# palette used by the rating heat-bar
# (`Games::RatingHeatBarComponent::TIERS` + the `very_bad` fall-
# through). The chip is used in the new bundle-modal "all games"
# table where a full-width gradient bar would compete with the dense
# tabular layout — a single solid-color pill is the right density.
#
# Reuses the heat-bar's class-level helpers
# (`Games::RatingHeatBarComponent.synthesized_score(game)` and
# `Games::RatingHeatBarComponent.tier_for(score)`) so the score and
# tier come from a single canonical source. Adding a new tier or
# changing the synthesis formula edits one place
# (`RatingHeatBarComponent`) and propagates to this chip for free.
#
# `TIER_BG_COLOR` is intentionally hard-coded to the project's vivid
# dark-theme palette in both themes. The chip carries the bg color as
# its only signal and the white text on a vivid background is the
# canonical readable form regardless of page theme. Tier semantics
# stay identical to the heat-bar; only the rendering surface differs.
#
# Returns nothing when the game has no synthesized score (no IGDB
# rating triplet with a positive vote count). The template branches on
# `score.present?` so the table cell renders blank rather than an
# em-dash — keeping the column visually quiet for rating-less games.
module Games
  class RatingScoreChipComponent < ViewComponent::Base
    # Tier → background hex. Mirrors the dark-theme `--color-rating-*`
    # tokens (vivid pop) so the chip reads loudly in both light and
    # dark themes. White chip text + a near-black 1px border (matches
    # the heat-bar score tick and the TTB pillar ticks for visual
    # parity).
    TIER_BG_COLOR = {
      "very_bad"  => "#7a2020",
      "bad"       => "#c08454",
      "poor"      => "#c08454",
      "meh"       => "#ffb86c",
      "fair"      => "#f1fa8c",
      "good"      => "#a8e063",
      "excellent" => "#50fa7b"
    }.freeze

    def initialize(game:)
      @game = game
    end

    def score
      Games::RatingHeatBarComponent.synthesized_score(@game)
    end

    def tier
      Games::RatingHeatBarComponent.tier_for(score)
    end

    def background_color
      TIER_BG_COLOR.fetch(tier, "#7a2020")
    end
  end
end
