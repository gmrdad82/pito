# 2026-05-17 BQ slice (item 8 of the 10-item /games/:id reshape list) —
# the variant showcase that briefly lived here has been cut down to a
# single canonical visualization: the **fuel gauge**. Variant 10 won
# the pick; the other nine variants (concentric / discs / rings / bars /
# columns / pyramid / clocks / ladder / stacked_timeline) plus the
# `ttb-showcase` scaffold are deleted from the component, ERB, view,
# and CSS.
#
# 2026-05-17 BZ+ restructure (user direction — "738h should scream at me"):
# the layout has been reshuffled into four stacked rows so the gauge
# reads as a labeled chart rather than a tick strip with floating
# captions.
#
#   row 1 — footage value text (top, centered on footage tick)
#   row 2 — TTB bar with 4 ticks (3 colored pillars + footage notch)
#   row 3 — pillar hour values (positioned BELOW each pillar tick)
#   row 4 — legend: 4 swatches + names (main / extras / completionist / recorded)
#
# Pillar tick colors moved from theme-text to a vivid literal palette
# that pops against the cool-spectrum gradient (periwinkle → cyan →
# indigo → magenta-purple):
#
#   main          #FFE74C  bright yellow
#   extras        #FFFFFF  pure white
#   completionist #FF4081  vivid pink/magenta
#
# Footage tick keeps its BB pattern unchanged (4px, page-bg fill +
# theme-text border). The legend's "recorded" swatch mirrors that
# styling (bg fill + 1px theme-text border) so the legend reads as a
# faithful key to the four marks on the bar.
#
# "Scream" mechanism for absurd completionist hours: append `🔥` when
# completionist > 200h, `🔥🔥` when > 500h. Footage trophy `🏆` from
# BQ is preserved unchanged for footage > completionist.
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

    # Per-pillar literal hex palette (BZ+ restructure). Theme-stable,
    # vivid, distinct against the bar's cool-spectrum gradient. The
    # legend swatches and pillar tick fills both pull from this map so
    # legend ⇔ tick color identity is 1:1 visible.
    PILLAR_COLOR = {
      main:          "#FFE74C",
      extras:        "#FFFFFF",
      completionist: "#FF4081"
    }.freeze

    # Thresholds for the "scream" mechanic on the completionist hour
    # value (appended to the bottom-row label). Two tiers so a 250h
    # game reads "🔥" while a 700h horror reads "🔥🔥".
    SCREAM_THRESHOLD_HOURS    = 200
    SCREAM_X2_THRESHOLD_HOURS = 500

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
    # em-dash when the pillar is missing (0 / nil). The completionist
    # pillar appends a scream emoji (🔥 / 🔥🔥) past the configured
    # absurdity thresholds so massive completionist projects visually
    # shout from the gauge.
    def label_for(key)
      h = hours[key].to_i
      return "—" unless h.positive?

      base = "#{h}h"
      return base unless key == :completionist

      "#{base}#{scream_suffix(h)}"
    end

    # Top-row label (above the bar): just the footage hours value (with
    # the BQ trophy preserved for over-completionist sessions). The
    # caption "recorded" lives in the legend row now — not below the
    # tick — so the bar's top edge stays uncluttered.
    def footage_value_label
      base = "#{footage_hours}h"
      compl = hours[:completionist].to_i
      footage_hours.positive? && compl.positive? && footage_hours > compl ? "#{base} 🏆" : base
    end

    # Legend caption for the footage swatch. Single word so the legend
    # row stays compact alongside the three pillar names.
    def footage_caption
      "recorded"
    end

    # Returns true when the footage tick should render at all. We
    # always render it for non-nil values (including 0) so the user
    # sees the "no footage recorded yet" tick parked at the left edge.
    def render_footage_tick?
      true
    end

    # Post-validation polish 5 — edge-label clamping. When a tick sits
    # near 0 % or 100 % of the bar, the default `translateX(-50%)` push
    # half the label outside the pane. The CSS modifier classes shift
    # the label so it aligns to the bar edge instead:
    #
    #   position < 10  → `--at-start` (left-aligned, no transform).
    #   position > 90  → `--at-end`   (right-aligned, translateX(-100%)).
    #   else           → `--centered` (default translateX(-50%)).
    #
    # Applied to every tick label (footage number, pillar hours) so no
    # label ever overflows the bar bounds regardless of the tick
    # position.
    def label_alignment_class(position_pct)
      pct = position_pct.to_f
      if pct < 10
        "ttb-fuel-gauge__label--at-start"
      elsif pct > 90
        "ttb-fuel-gauge__label--at-end"
      else
        "ttb-fuel-gauge__label--centered"
      end
    end

    private

    # Emoji escalation appended to the completionist hour value. Empty
    # string below SCREAM_THRESHOLD_HOURS; single `🔥` between the two
    # thresholds; double `🔥🔥` once past SCREAM_X2_THRESHOLD_HOURS.
    def scream_suffix(completionist_hours)
      if completionist_hours > SCREAM_X2_THRESHOLD_HOURS
        " 🔥🔥"
      elsif completionist_hours > SCREAM_THRESHOLD_HOURS
        " 🔥"
      else
        ""
      end
    end

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
