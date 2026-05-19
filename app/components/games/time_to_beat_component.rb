# 2026-05-19 v4 refactor — RHM-V5-shaped text bar.
#
# Bar shape (flexbox `__track` like RHM-V5):
#
#   [ ──────────────────────────────────────── ]
#    │     │            │                    │
#    main  extras   completionist          footage
#
# Where:
#   - `[` and `]` are bracket characters with `flex: 0 0 auto` so they
#     snap to the parent container's left/right edges.
#   - The fill (run of `─` glyphs) uses `flex: 1 1 auto` + `overflow:
#     hidden` so it expands to fill the available width regardless of
#     viewport.
#   - The fill carries a continuous Dracula ramp Green → Cyan → Yellow
#     → Pink via `background-clip: text; color: transparent;` on the
#     `__fill` span — coherent with the 4 Dracula tick colors below.
#   - Four `|` ticks (main, extras, completionist, footage) are
#     **absolutely positioned** over the bar at `left: <position>%`
#     with `transform: translateX(-50%)`. Each tick paints in its
#     category token color (`--color-ttb-main` / `--color-ttb-extras`
#     / `--color-ttb-completionist` / `--color-ttb-footage`).
#
# Rows around the bar (footage value above, pillar hour labels below,
# legend) retain their absolute-percent positioning model so they
# align with the same conceptual 0..100 axis as the ticks.
module Games
  class TimeToBeatComponent < ViewComponent::Base
    SAMPLE_HOURS = { main: 31, extras: 71, completionist: 124 }.freeze

    PILLAR_KEYS = %i[main extras completionist].freeze

    # Bottom-label collision model (kept verbatim from v3).
    BOTTOM_LABEL_COLLISION_THRESHOLD_PCT = 10.0
    NUDGE_PCT = 1.3

    def self.pillar_label
      {
        main:          I18n.t("games.ttb.main"),
        extras:        I18n.t("games.ttb.extras"),
        completionist: I18n.t("games.ttb.completionist")
      }.freeze
    end

    def initialize(game: nil, hours: nil, footage_hours: nil)
      @game           = game
      @hours          = hours
      @footage_hours  = footage_hours
    end

    def resyncing?
      @game&.resyncing? == true
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
      return @footage_hours.to_i if @footage_hours

      @game&.hours_of_footage.to_i
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
      return I18n.t("common.em_dash") unless h.positive?

      I18n.t("games.ttb.hours_short", n: h)
    end

    def footage_value_label
      h = footage_hours.to_i
      return I18n.t("common.em_dash") unless h.positive?

      I18n.t("games.ttb.hours_short", n: h)
    end

    def footage_caption
      I18n.t("games.ttb.footage")
    end

    def render_footage_tick?
      true
    end

    # Tick overlay data — one entry per category for the absolutely-
    # positioned `|` overlays. Each tick carries its CSS color-token
    # class so the template can paint it without per-template branches.
    # Ticks are suppressed while the game is resyncing; the bar
    # collapses to a flat gradient with no markers in that state.
    TICK_TOKEN_CLASS = {
      main:          "ttb-fuel-gauge__tick--main",
      extras:        "ttb-fuel-gauge__tick--extras",
      completionist: "ttb-fuel-gauge__tick--completionist",
      footage:       "ttb-fuel-gauge__tick--footage"
    }.freeze

    def tick_overlays
      return [] if resyncing?

      pillar_ticks = PILLAR_KEYS.map do |key|
        h = hours[key].to_i
        {
          key:         key,
          position:    position(h),
          token_class: TICK_TOKEN_CLASS[key]
        }
      end

      # 2026-05-20 — Always render the footage tick regardless of
      # measured hours. Missing data emits an em-dash bubble via
      # `footage_value_label` and positions at 0% (left edge); mirrors
      # the always-render policy applied to the 3 pillar ticks/labels.
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
        "ttb-fuel-gauge__label--at-start"
      elsif pct > 90
        "ttb-fuel-gauge__label--at-end"
      else
        "ttb-fuel-gauge__label--centered"
      end
    end

    def footage_label_alignment_class
      if footage_hours.to_i == 0
        "ttb-fuel-gauge__label--at-start"
      else
        "ttb-fuel-gauge__label--centered"
      end
    end

    def pillar_bottom_label_alignment_class
      "ttb-fuel-gauge__label--centered"
    end

    def pillar_label_data
      if resyncing?
        return PILLAR_KEYS.map do |key|
          {
            key:                key,
            hours:              hours[key].to_i,
            label:              label_for(key),
            position:           0.0,
            nudge:              nil,
            effective_position: 0.0
          }
        end
      end

      # 2026-05-20 — Always render all 3 pillar labels regardless of
      # measured hours. Missing data emits an em-dash label via
      # `label_for(key)` and positions at 0% (left edge); the tick is
      # likewise always rendered by `tick_overlays`.
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
      return 0.0 if resyncing?

      position(footage_hours)
    end

    # 2026-05-20 v4 — 14-stop hard-band gradient break positions.
    # Returns the six CSS percent strings (`p1`..`p6`) marking band
    # boundaries inside the three pillar segments on
    # `.ttb-fuel-gauge__fill`:
    #
    #   Main segment       (0 → p2)   : excellent (0..p1) / good (p1..p2)
    #   Extras segment     (p2 → p4)  : fair      (p2..p3) / meh  (p3..p4)
    #   Completionist seg. (p4 → 100) : poor (p4..p5) / bad (p5..p6) /
    #                                   very-bad (p6..100)
    #
    # Where:
    #   p2 = main_p, p4 = extras_p (from per-game pillar positions),
    #   p1 = mid of main segment, p3 = mid of extras segment,
    #   p5 = 1/3 into completionist, p6 = 2/3 into completionist.
    #
    # Used by the template to inject the values as inline CSS custom
    # properties (`--ttb-p1`..`--ttb-p6`) on the `__fill` element.
    #
    # Returns `nil` during resyncing — the stub layer renders flat
    # with even fallback distribution from the CSS defaults.
    def gradient_break_positions
      return nil if resyncing?

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
