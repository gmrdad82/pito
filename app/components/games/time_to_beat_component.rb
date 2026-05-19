# 2026-05-19 v3 refactor — TEXT BAR with full-width gradient + four
# `|` ticks (footage + main + extras + completionist).
#
# Bar shape (BAR_CELLS = 40):
#
#   [=======|==|==========|=================|]
#
# Where:
#   - `[` / `]` are bracket characters (theme-text color).
#   - The `=` characters fill EVERY cell between the brackets — the bar
#     shape is ALWAYS `[===…===]`. The cool-spectrum gradient
#     (green → lime → amber → pink) is painted on the `=` glyphs via
#     `background-clip: text; color: transparent;` on the `__fill`
#     spans.
#   - Four `|` ticks mark the positions of:
#       1. `footage_hours` — the user's recorded footage
#       2. main           — TTB main-story estimate
#       3. extras         — TTB main + extras estimate
#       4. completionist  — TTB completionist estimate
#     Each tick replaces one `=` at index `(value / max_x * N).round`.
#   - Ticks render in `var(--color-text)` (non-gradient) so the marker
#     stays visible regardless of which gradient stop it falls on.
#
# When two ticks land in the same cell, only one `|` is rendered there
# (the cell can only show one character). Pillar bottom labels keep the
# existing collision-nudge logic so the hour labels read clearly.
#
# The score-bubble, watermark, footage label, legend swatches, and
# below-bar pillar-hour labels are retained as row-level renderings
# around the text bar.
module Games
  class TimeToBeatComponent < ViewComponent::Base
    SAMPLE_HOURS = { main: 31, extras: 71, completionist: 124 }.freeze

    PILLAR_KEYS = %i[main extras completionist].freeze

    # Total cell count of the bar. Locked at 40 for monospace density
    # at the /games/:id pane width — wider than the rating heat bar's
    # 20 cells so the four ticks have room to separate.
    BAR_CELLS = 40

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

    # ------------------------------------------------------------------
    # Text-bar cell modeling.
    # ------------------------------------------------------------------

    # Cell index for a single tick value (hours). Returns the integer
    # cell whose left edge contains the value's projected percentage.
    # Clamped to [0, BAR_CELLS - 1]. Returns nil for non-positive values
    # so we don't drop a tick on cell 0 when the data is missing.
    def tick_index_for(value)
      h = value.to_i
      return nil unless h.positive?

      pct = position(h)
      idx = ((pct / 100.0) * BAR_CELLS).round
      idx.clamp(0, BAR_CELLS - 1)
    end

    # Cell indices currently occupied by a tick. Resyncing renders no
    # ticks (the bar reads as a flat gradient). The footage tick is
    # included alongside the three pillar ticks. Multiple ticks landing
    # on the same cell collapse to one `|`.
    def tick_cell_indices
      return [].to_set if resyncing?

      candidates = PILLAR_KEYS.map { |key| tick_index_for(hours[key]) }
      candidates << tick_index_for(footage_hours)
      candidates.compact.to_set
    end

    # Returns an array of `{ kind:, text: }` groups for rendering.
    # Adjacent cells of the same kind are merged so the gradient on
    # the `:fill` spans paints as a continuous strip.
    #
    # Every cell is either `:fill` (gradient `=`) or `:tick` (theme-text
    # `|`). No `:space` cells in v3 — the bar shape is always
    # `[===…===]` with ticks overriding individual cells.
    def cell_groups
      ticks = tick_cell_indices

      cells = (0...BAR_CELLS).map do |i|
        if ticks.include?(i)
          { kind: :tick, char: "|" }
        else
          { kind: :fill, char: "=" }
        end
      end

      cells.chunk_while { |a, b| a[:kind] == b[:kind] }.map do |group|
        { kind: group.first[:kind], text: group.map { |c| c[:char] }.join }
      end
    end

    def label_for(key)
      h = hours[key].to_i
      return I18n.t("common.em_dash") unless h.positive?

      I18n.t("games.ttb.hours_short", n: h)
    end

    def footage_value_label
      I18n.t("games.ttb.hours_short", n: footage_hours)
    end

    def footage_caption
      I18n.t("games.ttb.footage")
    end

    def render_footage_tick?
      true
    end

    # Below-bar pillar label data. The pillar label sits at the same
    # percent-along-the-bar as its tick character. Uses the existing
    # collision-resolution model (pull-apart) so labels at the bar's
    # left edge for main/extras don't overlap. `nudge` shifts each
    # colliding label outward by NUDGE_PCT.
    BOTTOM_LABEL_COLLISION_THRESHOLD_PCT = 10.0
    NUDGE_PCT = 1.3

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
