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
      # `w-screen` (not right-0): html reserves a stable 6px scrollbar gutter, so
      # right-0 would stop short of the true window edge. The window never scrolls
      # (the scrollback scrolls in an inner container), so 100vw reaches the edge
      # with no horizontal overflow.
      tag.div(
        Pito::Copy.render(BANNER_KEY),
        class: "fixed bottom-0 left-0 w-screen z-40 bg-red text-fg text-center " \
               "font-bold py-0.5 pointer-events-none select-none"
      )
    end
  end
end
