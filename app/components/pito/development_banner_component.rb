# frozen_string_literal: true

module Pito
  # Dev-only bottom banner so a development tab is unmistakable next to a
  # production one. Rendered from the application layout under a
  # `Rails.env.development?` guard; the label text comes from Pito::Copy
  # (`pito.copy.development.banner`), never hardcoded.
  #
  # Terminal-aesthetic: square corners, monospace, theme `accent-red` background
  # with the default foreground for readable contrast across every theme.
  # `pointer-events-none` so it never intercepts clicks on the status line below.
  class DevelopmentBannerComponent < ApplicationComponent
    BANNER_KEY = "pito.copy.development.banner"

    def call
      # Full-bleed bottom bar. right-0 reaches the true edge now that html no
      # longer reserves a dead scrollbar gutter (see application.css).
      tag.div(
        Pito::Copy.render(BANNER_KEY),
        class: "fixed bottom-0 left-0 right-0 z-40 bg-red text-fg text-center " \
               "font-bold py-0.5 pointer-events-none select-none"
      )
    end
  end
end
