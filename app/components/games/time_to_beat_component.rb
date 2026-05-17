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
# 2026-05-17 emoji strip (user direction — "Drop emoji. It adds too
# much. Keep it simple with text only."): the completionist scream
# escalation (🔥 / 🔥🔥) and the footage trophy (🏆 for footage >
# completionist) have both been removed. Labels are now plain
# `"<N>h"` strings only.
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

    # Heat-map gradient stops, anchored to FIXED HOUR thresholds (not
    # percentages). Each stop's percentage is computed per-game by
    # projecting its hour value onto `max_x`. The adaptive gradient
    # means:
    #
    #   - small max_x (e.g. Pragmata ~23h) → thresholds at 40 / 100h
    #     project past 100% and get clamped, so the bar is mostly green
    #     /lime with no orange or pink visible.
    #   - mid max_x (~100h) → all four stops land at 0 / 10 / 40 / 100%
    #     and the full ramp is visible.
    #   - large max_x (e.g. Crimson Desert ~775h) → 100h projects to
    #     ~13%, so green/lime/orange compress into the left ~13% and
    #     pink dominates the remaining ~87%.
    #
    # Pink (#E91E63) stays distinct from destructive red (#cc0000) —
    # this is "effort intensity" warning, not a destructive-action
    # signal. Locked 2026-05-17 (user direction — adaptive gradient).
    HEAT_THRESHOLDS = [
      [ 0,   "#4CAF50" ],   # low — green
      [ 10,  "#CDDC39" ],   # some — lime
      [ 40,  "#FFB74D" ],   # commitment — amber
      [ 100, "#E91E63" ]    # insanity — pink
    ].freeze

    # Per-pillar literal hex palette (BZ+ restructure). Theme-stable,
    # vivid, distinct against the bar's cool-spectrum gradient. The
    # legend swatches and pillar tick fills both pull from this map so
    # legend ⇔ tick color identity is 1:1 visible.
    PILLAR_COLOR = {
      main:          "#FFE74C",
      extras:        "#FFFFFF",
      completionist: "#FF4081"
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

    # CSS gradient-stops string for the bar's `background-image`,
    # computed per-game from `HEAT_THRESHOLDS` projected onto `max_x`.
    # See the constant's docstring for the adaptive behavior across
    # small / mid / large max_x values. Each threshold's percentage is
    # clamped to 100% so over-projecting stops don't break the CSS
    # gradient syntax. A trailing `<last-color> 100%` stop is appended
    # whenever the last threshold projects below 100%, so the bar
    # extends fully to its right edge even when the strongest color
    # never reaches the natural max.
    def gradient_stops
      stops = HEAT_THRESHOLDS.map do |hours, color|
        pct = [ (hours.to_f / max_x * 100).round(2), 100 ].min
        "#{color} #{pct}%"
      end
      stops << "#{HEAT_THRESHOLDS.last[1]} 100%" unless stops.last.end_with?("100%")
      stops.join(", ")
    end

    # `"31h"` / `"—"` style label for a single pillar. Falls back to
    # em-dash when the pillar is missing (0 / nil). Plain text, no
    # decoration — the emoji escalation was removed per user
    # direction (2026-05-17).
    def label_for(key)
      h = hours[key].to_i
      return "—" unless h.positive?

      "#{h}h"
    end

    # Top-row label (above the bar): just the footage hours value.
    # Plain text, no trophy — the over-completionist decoration was
    # removed per user direction (2026-05-17).
    def footage_value_label
      "#{footage_hours}h"
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
    # Applied to PILLAR labels only — the footage label uses
    # `footage_label_alignment_class` below and stays centered on its
    # tick regardless of position (overflow accepted per user
    # direction 2026-05-17 "the footage text 150h can be kept aligned
    # to the tick. there is no need for this one to be right aligned
    # in this case").
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

    # Footage value label alignment — ALWAYS centered on its tick. Per
    # user direction (2026-05-17): "the footage text 150h can be kept
    # aligned to the tick. there is no need for this one to be right
    # aligned in this case". Overflow past the bar's right edge is
    # accepted visually so the number stays visually anchored to the
    # footage notch even at >90 % position.
    def footage_label_alignment_class
      "ttb-fuel-gauge__label--centered"
    end

    # Bottom-row pillar label alignment — ALWAYS centered on its tick.
    # Per user direction (2026-05-17): "bottom texts for main, extra
    # and completionis, can stay with the pillar / tick in their
    # center. They won't overflow I think." The "Nh" labels are short
    # enough that centered placement keeps each label visually anchored
    # to its tick at any position, even near the bar's left / right
    # edge. Edge-clamping (`label_alignment_class`) is reserved for
    # cases where overflow would be visually unacceptable — bottom-row
    # pillar values opt out.
    def pillar_bottom_label_alignment_class
      "ttb-fuel-gauge__label--centered"
    end

    # Collision threshold (in percent of bar width). When two adjacent
    # pillar labels sit within this gap on the bar, the later label
    # bumps down a row so both remain readable. Picked at 10 % so the
    # Crimson Desert case (main 31h ≈ 4 %, extras 71h ≈ 9 %, both
    # under the bar's 775h max_x) resolves with extras bumped while
    # completionist (~95 %) stays in the top row.
    BOTTOM_LABEL_COLLISION_THRESHOLD_PCT = 10.0

    # Returns the bottom-row pillar labels with per-label collision
    # metadata so the template can render with `--bumped` applied to
    # any pillar that crowds its left neighbour.
    #
    # Each entry: `{ key:, hours:, label:, position:, bumped: }`.
    #
    #   key      — `:main` / `:extras` / `:completionist` (in pillar order).
    #   hours    — integer hours (0 / nil pillars are NOT skipped, so the
    #              em-dash label still renders in place).
    #   label    — string from `label_for(key)` ("31h" or "—").
    #   position — percent along the bar (already clamped 0..100).
    #   bumped   — true when this label's position sits within
    #              `BOTTOM_LABEL_COLLISION_THRESHOLD_PCT` of the
    #              previous rendered label's position.
    #
    # Collision detection runs against the **previous label's**
    # position only — so a chain of 3 tightly-packed labels gives
    # `[false, true, true]` (second bumps relative to first, third
    # bumps relative to second). The bump distance in CSS keeps both
    # bumped labels on the same lower row; tightly-packed triples
    # remain rare in practice (the user direction explicitly covers
    # the 2-collision Crimson Desert case).
    def pillar_label_data
      prev_pos = nil
      PILLAR_KEYS.map do |key|
        h   = hours[key].to_i
        pos = position(h)
        bumped = !prev_pos.nil? && (pos - prev_pos).abs < BOTTOM_LABEL_COLLISION_THRESHOLD_PCT
        prev_pos = pos
        {
          key:      key,
          hours:    h,
          label:    label_for(key),
          position: pos,
          bumped:   bumped
        }
      end
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
