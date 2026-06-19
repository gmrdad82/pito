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
#   footage_hours: (BigDecimal/Numeric, optional) — explicit footage hours
#                  (decimal, multiples of 0.5) override; default 0.
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
    # THEME-ADAPTIVE CONTRAST: each stop is mixed toward
    # `--fg-default` so the bar reads on ALL 18 themes. The light lime/amber
    # mids carry a heavier fg-mix (≈58%); the inherently-dark pink end only
    # ≈18%. Worst-case after the fix is 2.59:1 (catppuccin-latte / "low"),
    # vs 1.83:1 before; dark themes stay 3–8:1 and keep vivid accents. Mix
    # weights resolved with the OKLab+WCAG sweep script.
    HEAT_THRESHOLDS = [
      [ 0,   "color-mix(in oklch, var(--accent-green) 70%, var(--fg-default))" ],                                                 # low        — green
      [ 10,  "color-mix(in oklch, color-mix(in oklch, var(--accent-green), var(--accent-yellow)) 58%, var(--fg-default))" ],      # some       — lime
      [ 40,  "color-mix(in oklch, color-mix(in oklch, var(--accent-orange) 60%, var(--accent-yellow)) 58%, var(--fg-default))" ], # commitment — amber
      [ 100, "color-mix(in oklch, var(--accent-red), var(--accent-purple))" ]                                                    # insanity   — vivid pink (NOT fg-dimmed: the red+purple mix reads as the intended bright magenta on every theme)
    ].freeze

    # Terminal gradient colors for partial-data cases. These are the
    # same theme-aware color-mix pattern as HEAT_THRESHOLDS — no literal hex.
    #   extras-max  → ramp stops at yellow (no amber/pink past it)
    #   main-max    → ramp stops at green  (short-game all-green-ish fill)
    GRADIENT_TERMINAL_YELLOW = "color-mix(in oklch, var(--accent-yellow) 70%, var(--fg-default))"
    GRADIENT_TERMINAL_GREEN  = HEAT_THRESHOLDS[0][1]

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

    def initialize(game: nil, hours: nil, footage_hours: nil, label: nil)
      @game          = game
      @hours         = hours
      @footage_hours = footage_hours
      @label         = label
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
      @footage_hours || 0
    end

    # The largest PRESENT (positive) pillar hour value; 0 if all absent.
    # Used as the pillar-side base for effective_axis.
    def pillar_axis
      PILLAR_KEYS.filter_map { |k| hours[k].to_i.positive? ? hours[k].to_i : nil }.max || 0
    end

    # Effective scaling axis: the largest of (present pillars, footage if
    # present). All tick positions and gradient projections share this axis so
    # ticks, gradient, and footage bubble stay aligned.
    def effective_axis
      candidates = [ pillar_axis ]
      candidates << footage_hours if footage_hours.positive?
      candidates.max
    end

    def max_x
      ceiling = [ effective_axis, 10 ].max
      (ceiling * 1.05).round
    end

    # Color-projection axis (0..max_x). Used by `gradient_stops` so the heat
    # ramp reflects each game's absolute hour scale.
    def position(value)
      return 0.0 if max_x.zero?

      ((value.to_f / max_x) * 100).clamp(0.0, 100.0).round(3)
    end

    # Width of one `=` cell as a percentage of the bar (40 cells → 2.5%).
    CELL_WIDTH_PCT = 100.0 / BAR_CELLS

    # Tick axis end = effective_axis (largest present pillar or footage if
    # footage exceeds the pillars). When all pillars AND footage are absent,
    # returns 0 so tick_position short-circuits to 0.0 for everything.
    def tick_axis
      effective_axis
    end

    # Tick axis (0..tick_axis). 40 cells split that span into 2.5% slices; a
    # tick snaps to the MIDDLE of the cell its hour value falls in, so the
    # largest pillar lands at 98.75% — the middle of the last cell — rather than
    # flush against the closing bracket. Mirrors the ScoreBar needle snap.
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
    # The caller may pass an explicit `label:` (already space-padded) so the TTB
    # bar and the score bar in the same message align their brackets.
    def bar_label
      @label || Pito::Copy.render("pito.copy.game.ttb_label")
    end

    def footage_value_label
      Pito::Formatter::FootageHours.call(footage_hours)
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

    # Color-ramp axis for gradient projection.
    #
    # When completionist is present: axis = completionist (full ramp to pink).
    # When extras is the max-present pillar: axis = extras (ramp ends yellow).
    # When only main is present: axis = main (ramp ends green).
    # When all pillars absent: axis = 10 (safe minimum, footage-only or empty).
    #
    # The effective_axis may include footage (when footage > pillar max) so the
    # gradient and ticks share the same span, keeping them aligned.
    def color_axis_max
      [ effective_axis, 10 ].max
    end

    # Which pillar (if any) is the max-present pillar driving the gradient
    # terminal color. Returns :completionist, :extras, :main, or nil.
    def gradient_terminal_pillar
      PILLAR_KEYS.reverse.find { |k| hours[k].to_i.positive? }
    end

    # Terminal color for the gradient ramp:
    #   - completionist present → full ramp → pink (current behavior)
    #   - extras is max (no completionist) → yellow
    #   - main is max (no extras/completionist) → green
    #   - all absent → green (fallback; bar is essentially empty)
    def gradient_terminal_color
      case gradient_terminal_pillar
      when :completionist
        HEAT_THRESHOLDS.last[1]
      when :extras
        GRADIENT_TERMINAL_YELLOW
      else
        GRADIENT_TERMINAL_GREEN
      end
    end

    # The HEAT_THRESHOLDS stops to include in the gradient, based on the
    # highest present pillar. When completionist is absent, we truncate at
    # the appropriate tier so hotter colors don't bleed through:
    #   - completionist present → all 4 stops (up to pink)
    #   - extras max → stops 0..2 (green/lime/amber), then cap with yellow at 100%
    #   - main max / all absent → stop 0 only (green), then cap with green at 100%
    def gradient_threshold_stops
      case gradient_terminal_pillar
      when :completionist
        HEAT_THRESHOLDS
      when :extras
        HEAT_THRESHOLDS[0..2]
      else
        HEAT_THRESHOLDS[0..0]
      end
    end

    # CSS gradient-stops string for the fill's inline `background-image`
    # (clipped to the `=` glyphs). Projects HEAT_THRESHOLDS hour values onto
    # `color_axis_max` so the visible color spread reflects each game's actual
    # effort scale. When partial data is present the ramp is truncated so no
    # hotter colors appear past the highest present pillar. Colors
    # are the contrast-safe accent var()/color-mix() expressions — no hex.
    def gradient_stops
      stops = gradient_threshold_stops.map do |hours_threshold, color|
        pct = [ (hours_threshold.to_f / color_axis_max * 100).round(2), 100 ].min
        "#{color} #{pct}%"
      end

      # Append the terminal color at 100% (ensures the ramp reaches the right
      # edge with the correct partial-data color, not the last threshold's color
      # which may have been clamped short of 100%).
      terminal = "#{gradient_terminal_color} 100%"
      stops << terminal unless stops.last == terminal
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
