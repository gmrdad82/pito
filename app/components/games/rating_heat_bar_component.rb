# Wave C5 (2026-05-17) — Synthesized rating heat-bar.
# 2026-05-17 refresh — true heat-bar (gradient + indicator).
# 2026-05-17 two-variant compare — the prior 4-variant showcase
# (A/B/C/D) collapsed to TWO finalists rendered side-by-side on
# /games/:id so the user can compare and re-lock:
#
#   :red_only — gradient starts at `--color-rating-bad` (red); no
#               `very_bad` dark tone at all.
#   :very_bad — gradient starts at `--color-rating-very-bad` (dark
#               muddy red) at 0% then transitions to
#               `--color-rating-bad` at 25%, then climbs through
#               the higher tiers.
#
# Default variant is `:very_bad`. Both kwargs render through the same
# component; per-variant styling lives on the host element via the
# `rating-heat-bar--<variant>` modifier class. The variant kwarg + the
# compare scaffolding on /games/:id come back out once the user re-locks.
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

    VARIANTS = %i[red_only very_bad].freeze
    DEFAULT_VARIANT = :very_bad

    attr_reader :variant

    def initialize(game: nil, score: nil, variant: DEFAULT_VARIANT)
      @game     = game
      @override = score
      @variant  = VARIANTS.include?(variant) ? variant : DEFAULT_VARIANT
    end

    # Returns the score this bar renders. When `score:` was passed in
    # (override) it wins; otherwise we compute from the game's IGDB
    # rating triplets.
    def score
      return @override if @override

      synthesized_score
    end

    # Vote-weighted average across the three IGDB rating triplets.
    # Returns an integer in `0..100` when at least one source has
    # votes; nil otherwise.
    def synthesized_score
      return nil unless @game

      contributions = [
        [ @game.igdb_rating,       @game.igdb_rating_count ],
        [ @game.aggregated_rating, @game.aggregated_rating_count ],
        [ @game.total_rating,      @game.total_rating_count ]
      ].select { |s, count| s.present? && count.present? && count > 0 }

      return nil if contributions.empty?

      numerator   = contributions.sum { |s, count| s * count }
      denominator = contributions.sum { |_, count| count }
      (numerator / denominator).round
    end

    # CSS modifier suffix derived from the variant kwarg. Underscores
    # become hyphens so `:red_only` → `red-only`, matching the CSS
    # class naming convention used by the rest of the codebase.
    def variant_modifier
      variant.to_s.tr("_", "-")
    end

    # Tier slug for an arbitrary score. Exposed as a `data-tier`
    # attribute on the host element. Scores below 25 resolve to
    # `very_bad` (dark muddy red) per the AR carve-out.
    def tier_for(s)
      return "missing" if s.nil?

      TIERS.each do |min, name|
        return name if s >= min
      end
      "very_bad"
    end

    def tier
      tier_for(score)
    end
  end
end
