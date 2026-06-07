# frozen_string_literal: true

# KEPT BUT UNUSED — no host screen yet.
#
# Time-to-beat fuel gauge: a horizontal text bar with bracket edges,
# a continuous gradient fill, and four absolutely-positioned ticks
# (main / extras / completionist / footage).
#
# kwargs:
#   game:          (Game, optional) — source for ttb_*_seconds.
#   hours:         (Hash, optional) — explicit {main:, extras:, completionist:} override.
#   footage_hours: (Integer, optional) — explicit footage hour override; default 0.
module Pito
  class TimeToBeatComponent < ViewComponent::Base
    SAMPLE_HOURS = { main: 31, extras: 71, completionist: 124 }.freeze
    PILLAR_KEYS  = %i[main extras completionist].freeze

    # Cell count of the continuous `=` run between the brackets. 40 cells
    # span 0..completionist, so each `=` is a 2.5% slice and the
    # completionist tick lands in the middle of the last cell (98.75%).
    BAR_CELLS = 40

    # Heat-map gradient stops, anchored to FIXED HOUR thresholds (not
    # percentages). Each stop's percentage is computed per-game by
    # projecting its hour value onto `max_x`. The adaptive gradient means:
    #
    #   - small max_x (e.g. ~23h) → thresholds at 40/100h project past 100%
    #     and get clamped, so the bar is mostly green/lime.
    #   - mid max_x (~100h) → all four stops land at 0/10/40/100% and the
    #     full ramp is visible.
    #   - large max_x (e.g. ~775h) → 100h projects to ~13%, so green/lime/
    #     orange compress into the left ~13% and pink dominates.
    #
    # THEME-AWARE: each color is expressed against the active theme's accent
    # palette (--accent-* in themes.css) rather than literal hex, so the bar
    # adapts to all 18 themes. The mapping (effort tier → CSS color):
    #
    #   low         0h   → var(--accent-green)
    #   some        10h  → mix(green, yellow)        — lime
    #   commitment  40h  → mix(orange 60%, yellow)   — amber
    #   insanity    100h → mix(red, purple)          — magenta/pink
    #
    # color-mix uses oklch for smooth, non-muddy blends. The pink "insanity"
    # end stays distinct from destructive red — it is an "effort intensity"
    # signal, not an error. Mirrors the `.pito-ttb__fill` CSS ramp.
    #
    # THEME-ADAPTIVE CONTRAST (T17.1): each stop is mixed toward
    # `--fg-default` so the bar reads on ALL 18 themes. The light lime/amber
    # mids carry a heavier fg-mix (≈58%); the inherently-dark pink end only
    # ≈18%. Worst-case after the fix is 2.59:1 (catppuccin-latte / "low"),
    # vs 1.83:1 before; dark themes stay 3–8:1 and keep vivid accents. Mix
    # weights resolved with the OKLab+WCAG sweep script (Plan P17).
    HEAT_THRESHOLDS = [
      [ 0,   "color-mix(in oklch, var(--accent-green) 70%, var(--fg-default))" ],                                                 # low        — green
      [ 10,  "color-mix(in oklch, color-mix(in oklch, var(--accent-green), var(--accent-yellow)) 58%, var(--fg-default))" ],      # some       — lime
      [ 40,  "color-mix(in oklch, color-mix(in oklch, var(--accent-orange) 60%, var(--accent-yellow)) 58%, var(--fg-default))" ], # commitment — amber
      [ 100, "color-mix(in oklch, color-mix(in oklch, var(--accent-red), var(--accent-purple)) 82%, var(--fg-default))" ]         # insanity   — pink
    ].freeze

    # Bottom-label collision model.
    BOTTOM_LABEL_COLLISION_THRESHOLD_PCT = 10.0
    NUDGE_PCT = 1.3

    def self.pillar_label
      {
        main:          I18n.t("pito.game.ttb.main"),
        extras:        I18n.t("pito.game.ttb.extras"),
        completionist: I18n.t("pito.game.ttb.completionist")
      }.freeze
    end

    def initialize(game: nil, hours: nil, footage_hours: nil)
      @game          = game
      @hours         = hours
      @footage_hours = footage_hours
    end

    def hours
      return symbolize_hours(@hours) if @hours

      from_game = {
        main:          seconds_to_hours(@game&.ttb_main_seconds),
        extras:        seconds_to_hours(@game&.ttb_extras_seconds),
        completionist: seconds_to_hours(@game&.ttb_completionist_seconds)
      }

      from_game.values.all?(&:zero?) ? SAMPLE_HOURS.dup : from_game
    end

    def footage_hours
      @footage_hours.to_i
    end

    def max_x
      ceiling = [ hours[:completionist].to_i, footage_hours, 10 ].max
      (ceiling * 1.05).round
    end

    # Color-projection axis (0..max_x). Used by `gradient_stops` so the heat
    # ramp reflects each game's absolute hour scale; see T17.5.
    def position(value)
      return 0.0 if max_x.zero?

      ((value.to_f / max_x) * 100).clamp(0.0, 100.0).round(3)
    end

    # Width of one `=` cell as a percentage of the bar (40 cells → 2.5%).
    CELL_WIDTH_PCT = 100.0 / BAR_CELLS

    # Tick axis end = the LARGEST available pillar (normally completionist, but
    # when IGDB only returns a partial TTB — e.g. Crusader Kings 3 has main but
    # no extras/completionist — it falls back to the largest value present so
    # ticks don't all collapse to 0% from dividing by a zero completionist).
    def tick_axis
      [ hours[:main].to_i, hours[:extras].to_i, hours[:completionist].to_i ].max
    end

    # Tick axis (0..tick_axis). 40 cells split that span into 2.5% slices; a
    # tick snaps to the MIDDLE of the cell its hour value falls in, so the
    # largest pillar lands at 98.75% — the middle of the last cell — rather than
    # flush against the closing bracket. Mirrors the ScoreBar needle snap (T17.3).
    def tick_position(value)
      axis = tick_axis
      return 0.0 if axis.zero?

      raw  = (value.to_f / axis) * 100
      cell = (raw / CELL_WIDTH_PCT).floor.clamp(0, BAR_CELLS - 1)
      ((cell * CELL_WIDTH_PCT) + (CELL_WIDTH_PCT / 2.0)).round(3)
    end

    def label_for(key)
      h = hours[key].to_i
      return I18n.t("pito.game.ttb.em_dash") unless h.positive?

      I18n.t("pito.game.ttb.hours_short", n: h)
    end

    # Emit MORE `=` than can fit so the run fills 100% of the (full-width,
    # CSS-clipped) bar — not capped at BAR_CELLS. BAR_CELLS still drives the
    # tick cell-snap math (so completionist lands just inside the `]` bracket
    # rather than on it); the visible fill is continuous and full-width.
    FILL_CELLS = 300

    def fill_text
      "=" * FILL_CELLS
    end

    # Witty label rendered before the bar (e.g. "Hours needed"), via Pito::Copy.
    def bar_label
      Pito::Copy.render("pito.copy.game.ttb_label")
    end

    def footage_value_label
      h = footage_hours
      return I18n.t("pito.game.ttb.em_dash") unless h.positive?

      I18n.t("pito.game.ttb.hours_short", n: h)
    end

    def footage_caption
      I18n.t("pito.game.ttb.footage")
    end

    def render_footage_tick?
      true
    end

    TICK_TOKEN_CLASS = {
      main:          "ttb-tick--main",
      extras:        "ttb-tick--extras",
      completionist: "ttb-tick--completionist",
      footage:       "ttb-tick--footage"
    }.freeze

    def tick_overlays
      # Only render a tick for pillars IGDB actually returned — an absent
      # extras/completionist (0h) would otherwise pin a stray tick at the left.
      pillar_ticks = PILLAR_KEYS.filter_map do |key|
        h = hours[key].to_i
        next if h.zero?

        {
          key:         key,
          position:    tick_position(h),
          token_class: TICK_TOKEN_CLASS[key]
        }
      end

      if render_footage_tick?
        pillar_ticks << {
          key:         :footage,
          position:    tick_position(footage_hours),
          token_class: TICK_TOKEN_CLASS[:footage]
        }
      end

      pillar_ticks
    end

    def label_alignment_class(position_pct)
      pct = position_pct.to_f
      if pct < 10
        "ttb-label--at-start"
      elsif pct > 90
        "ttb-label--at-end"
      else
        "ttb-label--centered"
      end
    end

    def footage_label_alignment_class
      if footage_hours.zero?
        "ttb-label--at-start"
      else
        "ttb-label--centered"
      end
    end

    def pillar_bottom_label_alignment_class
      "ttb-label--centered"
    end

    def pillar_label_data
      # Skip absent pillars (0h) — no value label for data IGDB didn't return.
      ordered = PILLAR_KEYS.filter_map do |key|
        h = hours[key].to_i
        next if h.zero?

        {
          key:      key,
          hours:    h,
          label:    label_for(key),
          position: tick_position(h),
          nudge:    nil
        }
      end

      ordered.each_cons(2) do |a, b|
        if (b[:position] - a[:position]).abs < BOTTOM_LABEL_COLLISION_THRESHOLD_PCT
          a[:nudge] = :left if a[:nudge].nil?
          b[:nudge] = :right
        end
      end

      ordered.each do |entry|
        entry[:effective_position] = case entry[:nudge]
        when :left
          [ entry[:position] - NUDGE_PCT, 0.0 ].max
        when :right
          [ entry[:position] + NUDGE_PCT, 100.0 ].min
        else
          entry[:position]
        end
      end

      ordered
    end

    def footage_position
      tick_position(footage_hours)
    end

    def gradient_break_positions
      main_p   = position(hours[:main].to_i)
      extras_p = position(hours[:extras].to_i)

      half_extras = (extras_p - main_p) / 2.0
      comp_third  = (100 - extras_p) / 3.0

      {
        p1: format("%.2f%%", main_p / 2.0),
        p2: format("%.2f%%", main_p),
        p3: format("%.2f%%", main_p + half_extras),
        p4: format("%.2f%%", extras_p),
        p5: format("%.2f%%", extras_p + comp_third),
        p6: format("%.2f%%", extras_p + 2 * comp_third)
      }
    end

    # Color-ramp axis (0..completionist). The 40 `=` cells span exactly
    # 0..completionist, and the heat ramp is projected onto the SAME span so
    # the color under each cell is the heat color for that cell's absolute
    # hour count (T17.5). Floored at 10h so a tiny game can't divide by zero.
    def color_axis_max
      [ hours[:completionist].to_i, 10 ].max
    end

    # CSS gradient-stops string for the fill's inline `background-image`
    # (clipped to the `=` glyphs). Projects HEAT_THRESHOLDS hour values onto
    # `color_axis_max` (= completionist) so the visible color spread reflects
    # each game's actual effort scale: a short game (comp 30h) stays mostly
    # green/lime; a marathon (comp 700h) goes mostly pink because the 100h
    # "insanity" stop lands at ~14% and the pink fills the rest; a balanced
    # game (comp 80h) reads green→amber. Each percentage is clamped to 100%
    # so over-projecting stops don't break the CSS gradient syntax; a
    # trailing 100% stop is appended when the last threshold falls short so
    # the ramp reaches the right edge. Colors are the T17.1 contrast-safe
    # accent var()/color-mix() expressions (see HEAT_THRESHOLDS) — no hex.
    def gradient_stops
      stops = HEAT_THRESHOLDS.map do |hours_threshold, color|
        pct = [ (hours_threshold.to_f / color_axis_max * 100).round(2), 100 ].min
        "#{color} #{pct}%"
      end
      stops << "#{HEAT_THRESHOLDS.last[1]} 100%" unless stops.last.end_with?("100%")
      stops.join(", ")
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
