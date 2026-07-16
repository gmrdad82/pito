# frozen_string_literal: true

module Pito
  # The F9-toggled FPS chip (3.0.0) — a fixed top-left readout, hidden until
  # the owner presses F9 (the cross-surface perf keybind pito web shares with
  # pito-tui and pitomd). This is the new home of the fps meter that lived in
  # the dev banner since 2.1.0: the `#pito-fx-fps` span keeps its id and its
  # `pito--fx-fps` sampler, so the fx engine's `pito:fx:fps` events feed it
  # unchanged; the `pito--fps-overlay` wrapper is the F9 toggle's mount point.
  #
  # Rendered in EVERY environment (unlike the dev-only banner) — it is inert
  # while hidden: the sampler is visibility-gated, so an untoggled chip costs
  # nothing.
  class FpsOverlayComponent < ApplicationComponent
    def call
      tag.div(
        class: "pito-fps-overlay hidden fixed top-1 left-1 z-40 " \
               "text-fg-dim pointer-events-none select-none",
        data: { controller: "pito--fps-overlay" }
      ) do
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
