# frozen_string_literal: true

# KEPT BUT UNUSED — no host screen yet.
#
# Continuous rating bar with red→green gradient + absolute-positioned tick
# overlay + absolute-positioned score bubble.
#
# The score is read from `game.score` (the vote-weighted average
# computed by `Pito::Game::ScoreCalculator`).
#
# kwargs:
#   game:  (Game, optional) — source record for score synthesis.
#   score: (Integer, optional) — explicit override score; bypasses synthesis.
class Pito::ScoreBarComponent < ViewComponent::Base
  # The bar is full-width (CSS flex, like the TTB bar). We emit MORE `=` than
  # can ever fit and let CSS clip the overflow, so the `=` run fills 100% of
  # the available width at any container size. The red→green gradient is a CSS
  # background-clip:text over the visible box, so it scales with the width.
  FILL_CELLS = 160

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

    Pito::Game::ScoreCalculator.call(game)
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
    @game&.resyncing?
  end

  def overlay?
    !score.nil?
  end

  # Left offset (%) for the needle + bubble — the PRECISE score percent across
  # the full-width bar (0–100). No cell-snapping: an 81 sits at 81%.
  def overlay_left_percent
    return nil if score.nil?

    score.to_f.clamp(0.0, 100.0)
  end

  def fill_text
    "=" * FILL_CELLS
  end

  # Witty label rendered before the bar (e.g. "People Score"), via Pito::Copy.
  def score_label
    Pito::Copy.render("pito.copy.game.score_label")
  end
end
