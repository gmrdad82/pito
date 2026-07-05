# frozen_string_literal: true

module Pito
  module Shell
    # The pull-to-refresh indicator (G81/G93) — a kaomoji and one short ironic
    # line, revealed under the last message while the Android shell's bottom
    # pull (pito--pull-refresh) is in progress; flips to the armed color past
    # the reload threshold. Ships as an inert <template> in the layout so the
    # copy is server-resolved — BOTH halves are 50-variant dictionaries
    # sampled independently (G93: 50 glyphs × 50 lines = 2500 combos, so
    # repetition stays rare); never persisted, never visible outside a drag.
    class PullRefreshHintComponent < ViewComponent::Base
      TEMPLATE_ID = "pito-pull-refresh-hint"

      # Same gate as the refresh nudge: the scrollback is an authenticated
      # surface, and anonymous layouts stay free of chrome templates.
      def render?
        Current.session.present?
      end

      def glyph
        Pito::Copy.render("pito.copy.pull_refresh.glyphs")
      end

      def text
        Pito::Copy.render("pito.copy.pull_refresh.hints")
      end
    end
  end
end
