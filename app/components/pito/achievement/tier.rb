# frozen_string_literal: true

module Pito
  module Achievement
    # Shared tier data for the achievement subsystem.
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

      module_function

      # Channel-subs awards: threshold -> metal (channel scope only).
      # Since P25 the values live in config/pito/shinies.yml — every install
      # can carry its own ambitions (Pito::Achievements::Config validates).
      def awards
        Pito::Achievements::Config.awards
      end

      # Stone-ladder ceilings per scope x metric (the award thresholds sit
      # ABOVE the channel subs ceiling and are appended by series_for).
      def ceilings
        Pito::Achievements::Config.ceilings
      end

      # The 1-2-5 milestone series for a scope x metric, awards appended for
      # channel subs. Frozen + memoised per pair — the memo is keyed on the
      # loaded config document's identity, so a dev-reload or a spec's
      # reload! naturally invalidates it.
      #
      # @param scope  [String] "Channel" | "Video" | "Game" (polymorphic_name)
      # @param metric [String, Symbol]
      # @return [Array<Integer>]
      # @raise [KeyError] on an unknown scope/metric pair
      def series_for(scope:, metric:)
        doc = Pito::Achievements::Config.data
        @series = {} unless @series_doc.equal?(doc)
        @series_doc = doc
        @series[[ scope.to_s, metric.to_s ]] ||= begin
          max = ceilings.fetch(scope.to_s).fetch(metric.to_s)
          steps = []
          base = 1
          while base <= max
            [ 1, 2, 5 ].each do |k|
              v = base * k
              steps << v if v <= max
            end
            base *= 10
          end
          steps.concat(awards.keys) if award_track?(scope, metric)
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
        return awards[threshold] if award && awards.key?(threshold)

        series = series_for(scope:, metric:)
        series = series.reject { |t| awards.key?(t) } if award
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
