# Wave C5 (2026-05-17) — Synthesized rating heat-bar.
# 2026-05-19 v4 refactor — TEXT BAR with CONTINUOUS gradient + absolute-
# positioned tick overlay + absolute-positioned score bubble.
#
# Visual model:
#
#       87
#        v
#   [============|=========]
#
# Where:
#   - `[` and `]` are literal bracket characters (theme-text color).
#   - The full run of `=` characters between the brackets is ONE
#     continuous string. The full red→green gradient paints onto every
#     `=` glyph in a single pass via `background-clip: text;
#     color: transparent;` — no per-segment splits, no tick inserted
#     mid-string. Continuity of the underlying bar is preserved.
#   - When a score is present a single `|` tick is rendered as an
#     ABSOLUTE OVERLAY on top of the bar at `left: <score>%`. The tick
#     uses `var(--color-text)` so it remains visible regardless of
#     which gradient stop it lands on.
#   - The numeric score floats above the tick as a small bubble label,
#     also absolutely positioned at `left: <score>%`. A tiny pointer
#     glyph (`▼`) connects the bubble to the tick.
#   - With `score: nil` (or while resyncing) the bar still renders at
#     reduced opacity but the tick + bubble are omitted.
#
# AR carve-out (2026-05-17) — red (`--color-rating-bad`) is the BAD-zone
# color stop for the rating quality spectrum (per design.md + CLAUDE.md
# scoped exception).
#
# The score is the vote-weighted average of the three IGDB rating
# triplets carried on `Game`:
#
#   - `igdb_rating`       + `igdb_rating_count`
#   - `aggregated_rating` + `aggregated_rating_count`
#   - `total_rating`      + `total_rating_count`
#
# Returns `nil` when no source contributes. A nil score renders the
# muted variant (continuous `=` cells, dimmed, no tick, no bubble).
module Games
  class RatingHeatBarComponent < ViewComponent::Base
    # Cell count of the continuous `=` run between the brackets. 60
    # cells × ~7-8px monospace ≈ 420-480px which comfortably fills the
    # /games/:id left pane. The container has `width: 100%` and
    # `overflow: hidden` so on narrower viewports the right edge clips
    # gracefully against the closing bracket.
    BAR_CELLS = 60

    # Tier thresholds shared with `Games::RatingBadgeComponent`.
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

    def score
      return @override if @override

      self.class.synthesized_score(@game)
    end

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
      numerator.fdiv(denominator).round
    end

    def synthesized_score
      self.class.synthesized_score(@game)
    end

    def self.tier_for(s)
      return "missing" if s.nil?

      TIERS.each do |min, name|
        return name if s >= min
      end
      "very_bad"
    end

    def tier_for(s)
      self.class.tier_for(s)
    end

    def tier
      self.class.tier_for(score)
    end

    def resyncing?
      @game&.resyncing? == true
    end

    # Returns true when a tick + bubble overlay should be rendered. The
    # bar is always drawn; only the overlay is conditional.
    def overlay?
      !resyncing? && !score.nil?
    end

    # The `left:` percentage for the tick + bubble overlays. Clamped to
    # the visible range so a hypothetical score outside 0..100 still
    # parks the overlay on the bar.
    def overlay_left_percent
      return nil if score.nil?

      score.to_f.clamp(0.0, 100.0)
    end

    # Pre-built `=` run for the template. One continuous string — no
    # tick inserted mid-flow.
    def fill_text
      "=" * BAR_CELLS
    end
  end
end
