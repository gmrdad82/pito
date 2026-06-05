module Pito
  module Transitions
    # Pito::Transitions::ReducedMotion — anchor for the prefers-reduced-motion
    # contract. The actual enforcement happens client-side in the Stimulus
    # controller (which reads window.matchMedia("(prefers-reduced-motion: reduce)")).
    # This file documents the contract + exports the gate constants for the TUI
    # to read a config flag.
    #
    # When honored:
    #   - scramble-settle skipped → instant content swap
    #   - color-crossfade skipped → instant color swap
    #   - shimmer skipped → static muted color
    module ReducedMotion
      module_function

      CONFIG_KEY    = "transitions.reduced_motion"
      DEFAULT_VALUE = false
    end
  end
end
