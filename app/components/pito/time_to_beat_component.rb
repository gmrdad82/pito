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
