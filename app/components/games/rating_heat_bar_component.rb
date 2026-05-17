# Wave C5 (2026-05-17) — Synthesized rating heat-bar.
# 2026-05-17 refresh — true heat-bar (gradient + indicator).
# 2026-05-17 final lock — single canonical variant. The two-variant
# compare (`:red_only` / `:very_bad`) was used as a pick-off and is
# now collapsed back to a single render. The bar uses a three-zone
# pattern:
#
#   0-25%   solid `--color-rating-very-bad` (dark muddy red)
#   25-50%  solid `--color-rating-bad` (bright red), hard edge at 25
#   50-90%  smooth gradient through poor → meh → fair → good →
#           excellent (transition zone)
#   90-100% solid `--color-rating-excellent` (green), hard edge at 90
#
# The hard edges at 25, 50, and 90 are achieved with zero-distance
# stops (same percentage repeated) in the `linear-gradient`. The two
# end zones do not gradient at all — they read as solid blocks so
# the visual rule lands unambiguously: red = bad, green = gold,
# transition zone = in-between.
#
# 2026-05-17 AR carve-out — user approved red (`--color-rating-bad`)
# as the BAD-zone color stop for the rating quality spectrum AND a
# darker tone (`--color-rating-very-bad`, dark muddy red) as the
# worst-of-worst stop for scores below 25. See design.md + CLAUDE.md
# for the scoped exception to the global "red = destructive only" rule.
#
# The score is the vote-weighted average of the three IGDB rating
# triplets carried on `Game`:
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
# muted variant of the bar (`rating-heat-bar--muted`, no indicator)
# so the visual slot is preserved.
#
# Score override — pass `score:` directly to bypass the game-derived
# computation. Useful for tests / fixtures.
module Games
  class RatingHeatBarComponent < ViewComponent::Base
    # Tier thresholds shared with `Games::RatingBadgeComponent`. Inclusive
    # lower bound → tier slug. The slug feeds the `--color-rating-<slug>`
    # CSS variable. Scores below 25 fall through to `very_bad` (dark muddy
    # red); scores 25–49 resolve to `bad` (red — allowed here by the AR
    # carve-out; see header comment + design.md).
    TIERS = [
      [ 90, "excellent" ],
      [ 80, "good"      ],
      [ 70, "fair"      ],
      [ 60, "meh"       ],
      [ 50, "poor"      ],
      [ 25, "bad"       ]
    ].freeze

    def initialize(game: nil, score: nil)
      @game     = game
      @override = score
    end

    # Returns the score this bar renders. When `score:` was passed in
    # (override) it wins; otherwise we compute from the game's IGDB
    # rating triplets.
    def score
      return @override if @override

      self.class.synthesized_score(@game)
    end

    # Class-method form (2026-05-18) — vote-weighted average across the
    # three IGDB rating triplets carried on `Game`. Returns an integer
    # in `0..100` when at least one source has votes; nil otherwise.
    # Exposed at the class level so sibling components
    # (e.g. `Games::RatingScoreChipComponent`) can compute the same
    # canonical synthesized score without instantiating a heat-bar.
    def self.synthesized_score(game)
      return nil unless game

      contributions = [
        [ game.igdb_rating,       game.igdb_rating_count ],
        [ game.aggregated_rating, game.aggregated_rating_count ],
        [ game.total_rating,      game.total_rating_count ]
      ].select { |s, count| s.present? && count.present? && count > 0 }

      return nil if contributions.empty?

      numerator   = contributions.sum { |s, count| s * count }
      denominator = contributions.sum { |_, count| count }
      (numerator / denominator).round
    end

    # Instance-form preserved for backwards compatibility with the
    # existing template / specs that call `synthesized_score` directly
    # on the heat-bar instance.
    def synthesized_score
      self.class.synthesized_score(@game)
    end

    # Class-method form (2026-05-18) — tier slug for an arbitrary
    # numeric score (or nil). Scores below 25 resolve to `very_bad`
    # (dark muddy red) per the AR carve-out. Exposed at the class
    # level so sibling components can pick the same tier without
    # constructing a heat-bar instance.
    def self.tier_for(s)
      return "missing" if s.nil?

      TIERS.each do |min, name|
        return name if s >= min
      end
      "very_bad"
    end

    # Instance-form preserved for backwards compatibility.
    def tier_for(s)
      self.class.tier_for(s)
    end

    def tier
      self.class.tier_for(score)
    end
  end
end
