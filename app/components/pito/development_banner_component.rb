# frozen_string_literal: true

module Pito
  # Dev-only bottom ribbon. Since 2.1.0 it IS the fx debug meter (owner
  # 2026-07-13: the "DEVELOPMENT" wordmark is gone — the red ribbon itself
  # marks the environment; the meter is the content), raised off the screen
  # edge to sit close under the mini-status row instead of hugging the
  # viewport bottom.
  #
  # Terminal-aesthetic: square corners, monospace, theme `accent-red`
  # background. `pointer-events-none` so it never intercepts clicks.
  class DevelopmentBannerComponent < ApplicationComponent
    def call
      tag.div(
        class: "pito-dev-banner fixed bottom-1 left-0 right-0 z-40 bg-red text-fg text-center " \
               "font-bold py-0.5 pointer-events-none select-none"
      ) do
        # FX debug meter (2.1.0 F11): live frame rate — the page rAF, plus
        # the fx engine's own clock once it reports via `pito:fx:fps`.
        tag.span(
          "-- fps",
          id: "pito-fx-fps",
          class: "tabular-nums",
          data: { controller: "pito--fx-fps" }
        )
      end
    end
  end
end
