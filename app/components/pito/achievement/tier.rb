# frozen_string_literal: true

module Pito
  module Achievement
    # Shared tier data for the achievement subsystem (G127 rework).
    #
    # Ladders are PER SCOPE x METRIC (vid << game << channel - a game pools vids
    # across channels; the channel holds the whole library), each a 1-2-5 series
    # up to a ceiling anchored to the owner's target: a monetized, 100K-subs
    # channel (views ~ 200-500x subs lifetime, likes ~ views/30, comments ~
    # views/700).
    #
    # Materials are POSITIONAL on each ladder - eight natural stones, no metals:
    # every ladder's pinnacle is Opal, so 50K channel comments carries the same
    # valor as 50M channel views. The metals are reserved for the CHANNEL-SUBS
    # AWARDS (YouTube Creator Award scale): Silver 100K, Gold 1M, Diamond 10M -
    # appended to the channel subs series after the stone ceiling.
    module Tier
      STONES = %w[wood stone amber coral jade pearl ruby opal].freeze

      # Channel-subs awards: threshold -> metal (channel scope only).
      AWARDS = { 100_000 => "silver", 1_000_000 => "gold", 10_000_000 => "diamond" }.freeze

      # Stone-ladder ceilings per scope x metric (the award thresholds sit
      # ABOVE the channel subs ceiling and are appended by series_for).
      CEILINGS = {
        "Video"   => { "views" => 1_000_000,  "watched_hours" => 100_000,
                       "likes" => 20_000,     "comments" => 5_000, "subs_gained" => 5_000 }.freeze,
        "Game"    => { "views" => 10_000_000, "watched_hours" => 500_000,
                       "likes" => 200_000,    "comments" => 20_000, "subs_gained" => 10_000 }.freeze,
        "Channel" => { "views" => 50_000_000, "watched_hours" => 2_000_000,
                       "likes" => 500_000,    "comments" => 50_000, "subs" => 50_000 }.freeze
      }.freeze

      module_function

      # The 1-2-5 milestone series for a scope x metric, awards appended for
      # channel subs. Frozen + memoised per pair.
      #
      # @param scope  [String] "Channel" | "Video" | "Game" (polymorphic_name)
      # @param metric [String, Symbol]
      # @return [Array<Integer>]
      # @raise [KeyError] on an unknown scope/metric pair
      def series_for(scope:, metric:)
        @series ||= {}
        @series[[ scope.to_s, metric.to_s ]] ||= begin
          max = CEILINGS.fetch(scope.to_s).fetch(metric.to_s)
          steps = []
          base = 1
          while base <= max
            [ 1, 2, 5 ].each do |k|
              v = base * k
              steps << v if v <= max
            end
            base *= 10
          end
          steps.concat(AWARDS.keys) if award_track?(scope, metric)
          steps.freeze
        end
      end

      # The material string for one threshold on its ladder: an award metal on
      # the channel-subs award steps, else the POSITIONAL stone (pinnacle stone
      # step = opal). Off-ladder thresholds (legacy rows) fall back to the
      # nearest lower step rather than raising.
      #
      # @return [String] one of STONES or AWARDS.values
      def material_for(scope:, metric:, threshold:)
        award = award_track?(scope, metric)
        return AWARDS[threshold] if award && AWARDS.key?(threshold)

        series = series_for(scope:, metric:)
        series = series.reject { |t| AWARDS.key?(t) } if award
        idx = series.index(threshold) || series.rindex { |t| t <= threshold } || 0
        return STONES.last if idx == series.length - 1

        STONES[[ (idx.to_f / (series.length - 1) * STONES.length).floor, STONES.length - 1 ].min]
      end

      # True when this scope x metric carries the metal awards (channel subs).
      def award_track?(scope, metric)
        scope.to_s == "Channel" && metric.to_s == "subs"
      end
    end
  end
end
