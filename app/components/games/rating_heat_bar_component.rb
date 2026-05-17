# Wave C5 (2026-05-17) — Synthesized rating heat-bar.
#
# Renders a fixed-width horizontal bar whose fill width (0..100%) and
# fill color represent the vote-weighted average of the three IGDB
# rating triplets carried on `Game`:
#
#   - `igdb_rating`       + `igdb_rating_count`
#   - `aggregated_rating` + `aggregated_rating_count`
#   - `total_rating`      + `total_rating_count`
#
# Formula (LOCKED — spec 08 §"Rating heat-bar synthesis"):
#
#   contributions = each (score, count) pair where both are present
#                    and count > 0
#   score = round( sum(score * count) / sum(count) )
#
# Returns `nil` when no source contributes. A nil score renders the
# muted variant of the bar (`rating-heat-bar--muted`, em-dash label,
# 0% fill) so the visual slot is preserved.
#
# Tier color reuses `Games::RatingBadgeComponent::TIERS` so the
# heat-bar fill tracks the same `--color-rating-*` palette as the
# colored badges scattered across the rest of the game surfaces.
# Theme variants (light / dark) come for free from the existing CSS
# variables.
module Games
  class RatingHeatBarComponent < ViewComponent::Base
    def initialize(game:)
      @game = game
    end

    # Vote-weighted average across the three IGDB rating triplets.
    # Returns an integer in `0..100` when at least one source has
    # votes; nil otherwise.
    def synthesized_score
      contributions = [
        [ @game.igdb_rating,       @game.igdb_rating_count ],
        [ @game.aggregated_rating, @game.aggregated_rating_count ],
        [ @game.total_rating,      @game.total_rating_count ]
      ].select { |score, count| score.present? && count.present? && count > 0 }

      return nil if contributions.empty?

      numerator   = contributions.sum { |score, count| score * count }
      denominator = contributions.sum { |_, count| count }
      (numerator / denominator).round
    end

    # Maps a 0..100 score to the same `--color-rating-<tier>` palette
    # `Games::RatingBadgeComponent` uses. Anything below the lowest
    # tier threshold falls into "bad".
    def tier_color(score)
      tier = Games::RatingBadgeComponent::TIERS.find { |min, _| score >= min }&.last || "bad"
      "var(--color-rating-#{tier})"
    end
  end
end
