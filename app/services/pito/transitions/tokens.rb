module Pito
  module Transitions
    # Pito::Transitions::Tokens — canonical timing/easing constants for the
    # 2-effect transition system + shimmer decoration. Single source of truth.
    # Exported to:
    #   - app/assets/tailwind/_theme.css  (CSS custom properties --tui-trn-*)
    #
    # Adding a token = add constant here + run rake pito:transitions:export.
    module Tokens
      module_function

      SCRAMBLE_DURATION_MS = 200
      SCRAMBLE_STAGGER_MS  = 30
      SCRAMBLE_FRAME_MS    = 30

      COLOR_CROSSFADE_DURATION_MS = 300
      COLOR_CROSSFADE_EASING      = "ease-out"

      SHIMMER_CYCLE_MS       = 1600
      SHIMMER_GRADIENT_STOPS = "muted 0%, muted 40%, accent 50%, muted 60%, muted 100%"

      DEBOUNCE_MS = 80

      ALL = {
        scramble_duration_ms: SCRAMBLE_DURATION_MS,
        scramble_stagger_ms: SCRAMBLE_STAGGER_MS,
        scramble_frame_ms: SCRAMBLE_FRAME_MS,
        color_crossfade_duration_ms: COLOR_CROSSFADE_DURATION_MS,
        color_crossfade_easing: COLOR_CROSSFADE_EASING,
        shimmer_cycle_ms: SHIMMER_CYCLE_MS,
        shimmer_gradient_stops: SHIMMER_GRADIENT_STOPS,
        debounce_ms: DEBOUNCE_MS
      }.freeze
    end
  end
end
