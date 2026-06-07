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

    def position(value)
      return 0.0 if max_x.zero?

      ((value.to_f / max_x) * 100).clamp(0.0, 100.0).round(3)
    end

    def label_for(key)
      h = hours[key].to_i
      return I18n.t("pito.game.ttb.em_dash") unless h.positive?

      I18n.t("pito.game.ttb.hours_short", n: h)
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
      pillar_ticks = PILLAR_KEYS.map do |key|
        h = hours[key].to_i
        {
          key:         key,
          position:    position(h),
          token_class: TICK_TOKEN_CLASS[key]
        }
      end

      if render_footage_tick?
        pillar_ticks << {
          key:         :footage,
          position:    position(footage_hours),
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
      ordered = PILLAR_KEYS.map do |key|
        h = hours[key].to_i
        {
          key:      key,
          hours:    h,
          label:    label_for(key),
          position: position(h),
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
      position(footage_hours)
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

    # CSS gradient-stops string for the bar's inline `background-image`.
    # Projects HEAT_THRESHOLDS hour values onto `max_x` so the visible
    # color spread reflects each game's actual effort scale. Each
    # threshold's percentage is clamped to 100% so over-projecting stops
    # don't break the CSS gradient syntax. A trailing stop at 100% is
    # appended whenever the last threshold projects below 100% so the bar
    # extends fully to its right edge. Colors are theme accent var()/
    # color-mix() expressions (see HEAT_THRESHOLDS) — no literal hex.
    def gradient_stops
      stops = HEAT_THRESHOLDS.map do |hours_threshold, color|
        pct = [ (hours_threshold.to_f / max_x * 100).round(2), 100 ].min
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
