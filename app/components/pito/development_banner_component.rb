# frozen_string_literal: true

module Pito
  # Dev-only bottom ribbon so a development tab is unmistakable next to a
  # production one. Rendered from the application layout under a
  # `Rails.env.development?` guard.
  #
  # History: shipped as a plain "DEVELOPMENT" wordmark; since 2.1.0 it
  # briefly IS'd the fx debug meter itself (owner 2026-07-13: red ribbon
  # marks the environment, `#pito-fx-fps` was the content). Owner
  # (2026-07-15): that meter moves to a toggleable top-left chip
  # (`Pito::FpsOverlayComponent`, F9) — its own deliverable — so the wordmark
  # returns here as the environment marker.
  #
  # Terminal-aesthetic: square corners, monospace, theme `accent-red`
  # background. `pointer-events-none` so it never intercepts clicks.
  class DevelopmentBannerComponent < ApplicationComponent
    # Hardcoded rather than routed through Pito::Copy: this is an
    # environment marker (dev vs. prod tab), not user-facing product copy,
    # so it's exempt from the copy-dictionary law. No
    # `pito.copy.development.banner` key currently exists — it was dropped
    # in 3095f1b6 when the meter took the ribbon over.
    WORDMARK = "DEVELOPMENT"

    def call
      tag.div(
        WORDMARK,
        class: "pito-dev-banner fixed bottom-1 left-0 right-0 z-40 bg-red text-fg text-center " \
               "font-bold py-0.5 pointer-events-none select-none"
      )
    end
  end
end
