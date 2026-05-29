module Pito
  module Transitions
    # Pito::Transitions::Effects — canonical effect registry. 2 transitions +
    # 1 decoration. Adding a new effect requires entries here + JS controller
    # impl + parity spec passing. Frozen at boot.
    module Effects
      EFFECTS = {
        scramble_settle: {
          kind: :transition,
          purpose: "content change (text, numbers, words; per-char scramble; diff-only)",
          tokens: %i[scramble_duration_ms scramble_stagger_ms scramble_frame_ms]
        },
        color_crossfade: {
          kind: :transition,
          purpose: "color change (only fires on computed-color diff)",
          tokens: %i[color_crossfade_duration_ms color_crossfade_easing]
        },
        shimmer: {
          kind: :decoration,
          purpose: "continuous indicator (currently sync VC syncing state only)",
          tokens: %i[shimmer_cycle_ms shimmer_gradient_stops]
        }
      }.freeze

      def self.transition_names
        EFFECTS.select { |_, v| v[:kind] == :transition }.keys
      end

      def self.decoration_names
        EFFECTS.select { |_, v| v[:kind] == :decoration }.keys
      end

      def self.all_names
        EFFECTS.keys
      end
    end
  end
end
