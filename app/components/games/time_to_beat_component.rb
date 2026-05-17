# 2026-05-17 BQ slice (item 8 of the 10-item /games/:id reshape list) —
# the variant showcase that briefly lived here has been cut down to a
# single canonical visualization: the **fuel gauge**. Variant 10 won
# the pick; the other nine variants (concentric / discs / rings / bars /
# columns / pyramid / clocks / ladder / stacked_timeline) plus the
# `ttb-showcase` scaffold are deleted from the component, ERB, view,
# and CSS.
#
# Fuel-gauge layout (single render, full RIGHT-pane width):
#
#   recorded 87h                                    <— footage label
#   31h          71h               124h             <— pillar values above
#   ▲             ▲                 ▲           ▮   <— ticks (thin, no border)
#                                              footage tick: bigger + bordered
#   main        extras         completionist       <— pillar names below
#
# Hours, not percentages. The bar's x-axis runs `0..max_x`. `max_x` is
# `max(completionist, footage) * 1.05` (5% breathing room on the right)
# so even when footage exceeds completionist the over-zone fits with
# slack. The four background zones are:
#
#   0-10h    "low effort"   — muted dark grey
#   10-40h   "some effort"  — muted slate
#   40-100h  "commitment"   — steel blue
#   100h+    "insanity"     — muted plum
#
# The palette is intentionally neutral (no theme-flip): a single literal
# hex per zone in both light and dark. It avoids the colors that other
# components reserve: red / orange / yellow (heat bar gradient), green
# (status accents), pure blue (`--color-chart-1` link blue). The result
# reads as "calming weight ramp" — the bar's color tells you how much of
# a commitment the game's full-effort milestones represent without
# competing with chips / heat-bar / status.
#
# Footage tick is the focal point. It's wider (4px vs 2px for pillar
# ticks), tall enough to overshoot the bar top + bottom, and carries a
# theme-aware border (`var(--color-text)`) — exactly the BB pattern
# used by `.rating-heat-bar-indicator` for the score notch on the heat
# bar. The label above reads `"recorded Nh"`. When `footage >
# completionist`, a small trophy glyph `🏆` is appended to the label
# (visual flourish for "you went past the full-effort milestone").
module Games
  class TimeToBeatComponent < ViewComponent::Base
    # Sample triplet used when the game has no IGDB time-to-beat data.
    # Picked to match the user's reference screenshot (31 / 71 / 124)
    # so the gauge always renders something compelling even on a fresh
    # / unsynced row.
    SAMPLE_HOURS = { main: 31, extras: 71, completionist: 124 }.freeze

    PILLAR_KEYS = %i[main extras completionist].freeze

    PILLAR_LABEL = {
      main:          "main",
      extras:        "extras",
      completionist: "completionist"
    }.freeze

    # Zone boundaries (in hours). Used by the ERB to compute the left+
    # right edge of each zone as a percentage of `max_x`. Open-ended
    # top zone (`100..`) extends to `max_x`.
    ZONE_BOUNDARIES_HOURS = [ 10, 40, 100 ].freeze

    # Backwards-compat aliases for any caller / spec that previously
    # introspected the per-pillar color map. The fuel gauge does not
    # use per-pillar colors anymore — the bar's zones encode effort,
    # not pillar identity — but the labels still ride the same
    # vocabulary so we keep the constant exposed for parity.
    PILLAR_COLOR = {
      main:          "var(--color-text)",
      extras:        "var(--color-text)",
      completionist: "var(--color-text)"
    }.freeze

    def initialize(game: nil, hours: nil, footage_hours: nil)
      @game           = game
      @hours          = hours
      @footage_hours  = footage_hours
    end

    # Returns `{ main:, extras:, completionist: }` as Integers (hours).
    # Resolution order:
    #   1. explicit `hours:` kwarg (used by previews / specs).
    #   2. the game's IGDB ttb_* seconds, converted to whole hours.
    #   3. SAMPLE_HOURS when (2) yields all-zero / nil.
    def hours
      return symbolize_hours(@hours) if @hours

      from_game = {
        main:          seconds_to_hours(@game&.ttb_main_seconds),
        extras:        seconds_to_hours(@game&.ttb_extras_seconds),
        completionist: seconds_to_hours(@game&.ttb_completionist_seconds)
      }

      from_game.values.all?(&:zero?) ? SAMPLE_HOURS.dup : from_game
    end

    # Hours of footage recorded for this game. Explicit kwarg wins; else
    # `Game#hours_of_footage` (manual override → cached value); else 0.
    def footage_hours
      return @footage_hours.to_i if @footage_hours

      @game&.hours_of_footage.to_i
    end

    # The bar's x-axis upper bound. 5% slack past
    # `max(completionist, footage)` so even an over-completionist
    # footage tick has breathing room on the right edge. Minimum of
    # 10h so a fresh game with all-zero pillars + zero footage still
    # renders a meaningful gauge (anchored to the low-effort zone).
    def max_x
      ceiling = [ hours[:completionist].to_i, footage_hours, 10 ].max
      (ceiling * 1.05).round
    end

    # `(value / max_x) * 100`, clamped to [0, 100]. Used to position
    # ticks and zone edges along the bar.
    def position(value)
      return 0.0 if max_x.zero?

      ((value.to_f / max_x) * 100).clamp(0.0, 100.0).round(3)
    end

    # `"31h"` / `"—"` style label for a single pillar. Falls back to
    # em-dash when the pillar is missing (0 / nil).
    def label_for(key)
      h = hours[key].to_i
      h.positive? ? "#{h}h" : "—"
    end

    # `"recorded 87h"` for a present footage value; `"recorded 0h"` for
    # zero (signals "we know it's zero, not unknown"); appends a 🏆
    # glyph when footage exceeds completionist (the "you went past the
    # commitment milestone" visual flourish).
    def footage_label
      base = "recorded #{footage_hours}h"
      compl = hours[:completionist].to_i
      footage_hours.positive? && compl.positive? && footage_hours > compl ? "#{base} 🏆" : base
    end

    # Returns true when the footage tick should render at all. We
    # always render it for non-nil values (including 0) so the user
    # sees the "no footage recorded yet" tick parked at the left edge.
    def render_footage_tick?
      true
    end

    private

    def seconds_to_hours(seconds)
      return 0 if seconds.nil? || seconds.to_i <= 0

      (seconds.to_f / 3600).round
    end

    def symbolize_hours(input)
      {
        main:          (input[:main]          || input["main"]          || 0).to_i,
        extras:        (input[:extras]        || input["extras"]        || 0).to_i,
        completionist: (input[:completionist] || input["completionist"] || 0).to_i
      }
    end
  end
end
