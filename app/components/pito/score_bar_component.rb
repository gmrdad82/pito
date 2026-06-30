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
  FILL_CELLS = 300

  TIERS = [
    [ 90, "excellent" ],
    [ 80, "good"      ],
    [ 70, "fair"      ],
    [ 60, "meh"       ],
    [ 50, "poor"      ],
    [ 25, "bad"       ]
  ].freeze

  def initialize(game: nil, score: nil, show_label: true, label: nil)
    @game       = game
    @override   = score
    @show_label = show_label
    @label      = label
  end

  # Whether to render the witty Pito::Copy label before the bar. The game
  # detail message keeps it (default); recommendation surfaces (channel item)
  # pass false since the surrounding context already names the score.
  def show_label?
    @show_label
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

  # Left offset (%) for the marker — the PRECISE score percent across the
  # full-width bar, CLAMPED to 1–99 so a 0 or 100 marker is never clipped off the
  # track edge. The DISPLAYED number stays the real score (0/100); only the
  # POSITION is clamped (13.4).
  def overlay_position_percent
    return nil if score.nil?

    score.to_f.clamp(1.0, 99.0)
  end

  # Which side of the pillar the inline score value sits on: for a LOW score (< 50)
  # the pillar is near the left, so the value goes to its RIGHT (reads into the bar);
  # for a HIGH score (>= 50) the pillar is near the right, so the value goes to its
  # LEFT. Either way the value never touches the pillar (13.17).
  def value_side_class
    return "" if score.nil?

    score < 50 ? "pito-score-bar__marker--value-right" : "pito-score-bar__marker--value-left"
  end

  def fill_text
    "=" * FILL_CELLS
  end

  # Witty label rendered before the bar (e.g. "People Score"), via Pito::Copy.
  # The caller may pass an explicit `label:` (already space-padded) so the score
  # bar and the TTB bar in the same message align their brackets.
  def score_label
    @label || Pito::Copy.render("pito.copy.game.score_label")
  end

  # Stagger bucket for the bar shimmer animation. Combines the label text and
  # the score value so that bars for different scores (or score vs TTB in the
  # same card) scatter to different delays and never pulse in sync.
  def shimmer_offset_class
    Pito::Shimmer.offset_class("#{score_label}#{score}")
  end
end
