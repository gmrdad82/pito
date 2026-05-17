# Wave C7 variants pass (2026-05-17) — Time-to-beat visualization
# showcase. The /games/:id RIGHT pane previously rendered the three
# IGDB time-to-beat pillars (main / extras / completionist) as a flat
# three-column table; we now render a *showcase* of 10 candidate
# visual treatments stacked vertically so the user can pick one.
#
# Each variant accepts the same input — a `game:` (preferred) or an
# explicit `hours:` hash `{ main:, extras:, completionist: }`. Game-
# derived hours come from `Game#ttb_*_seconds`, rounded half-up to
# whole hours (matches `GamesHelper#ttb_hours`). When a game has no
# IGDB time-to-beat data at all, the component falls back to a
# sample triplet so the showcase reads as a visual comparison rather
# than collapsing to em-dashes.
#
# Variants:
#
#   :concentric       — three nested SVG circles (main ⊂ extras ⊂
#                       completionist), radii proportional to hours.
#   :discs            — three filled SVG discs in a row, diameter ∝ hours.
#   :rings            — three Apple-Watch-style activity rings, each filled
#                       as a fraction of the completionist max.
#   :bars             — three horizontal bars stacked, width ∝ hours.
#   :columns          — three vertical bars side-by-side, height ∝ hours.
#   :pyramid          — three stacked rectangles widening downward.
#   :clocks           — three SVG clock faces with a filled wedge for the
#                       hours-modulo-12 fraction of a full revolution.
#   :ladder           — sparkline ladder: three notches plotted at
#                       (1, main), (2, extras), (3, completionist) on an
#                       implicit y-axis.
#   :stacked_timeline — single continuous horizontal bar segmented into
#                       three regions; reads as "main → +extras →
#                       +completionist" along one effort timeline. The
#                       extras segment is the *delta* (extras − main); the
#                       completionist segment is (completionist − extras).
#                       Bonus invented variant.
#   :fuel_gauge       — horizontal gauge running 0 → completionist with
#                       three tick marks at main / extras / completionist.
#                       The bar is filled to the completionist mark; ticks
#                       above carry the labels. Bonus invented variant.
#
# All variants use design.md tokens — `--color-text`, `--color-muted`,
# `--color-border`, and the existing `--color-chart-N` palette for the
# three pillars (main = chart-1 / extras = chart-2 / completionist =
# chart-3). No new colors are invented.
module Games
  class TimeToBeatComponent < ViewComponent::Base
    VARIANTS = %i[
      concentric
      discs
      rings
      bars
      columns
      pyramid
      clocks
      ladder
      stacked_timeline
      fuel_gauge
    ].freeze

    # Sample triplet used when no game is provided OR the game has no
    # IGDB time-to-beat data. Picked to match the user's reference
    # screenshot (31 / 71 / 124) so the showcase always renders
    # something compelling.
    SAMPLE_HOURS = { main: 31, extras: 71, completionist: 124 }.freeze

    # Per-pillar color tokens. Reuses the canonical chart palette so
    # the showcase visuals tie back to the existing design system.
    PILLAR_COLOR = {
      main:          "var(--color-chart-1)",
      extras:        "var(--color-chart-2)",
      completionist: "var(--color-chart-3)"
    }.freeze

    PILLAR_LABEL = {
      main:          "main",
      extras:        "extras",
      completionist: "completionist"
    }.freeze

    PILLAR_KEYS = %i[main extras completionist].freeze

    def initialize(game: nil, hours: nil, variant: :concentric)
      raise ArgumentError, "unknown variant: #{variant.inspect}" unless VARIANTS.include?(variant)

      @game    = game
      @hours   = hours
      @variant = variant
    end

    attr_reader :variant

    # Returns `{ main:, extras:, completionist: }` as Integers (hours).
    # Resolution order:
    #   1. explicit `hours:` kwarg (used by future showcase callers /
    #      previews that want a fixed sample).
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

    # Whichever pillar carries the largest hour count — used by ratio-
    # based variants (rings, bars, columns, pyramid, ladder, gauge).
    # Falls back to 1 to avoid div-by-zero when every pillar is zero.
    def max_hours
      [ hours.values.max.to_i, 1 ].max
    end

    # Per-pillar fraction of `max_hours`, clamped to 0.0..1.0. Useful
    # for any variant that maps hour count to a 0..1 scalar.
    def fraction_for(key)
      raw = hours[key].to_f / max_hours
      raw.clamp(0.0, 1.0)
    end

    # `"31h"` / `"—"` style label for a single pillar. Falls back to
    # em-dash when the pillar is missing (0 / nil) so the showcase
    # mirrors the helper's behavior in flat-table mode.
    def label_for(key)
      h = hours[key].to_i
      h.positive? ? "#{h}h" : "—"
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
