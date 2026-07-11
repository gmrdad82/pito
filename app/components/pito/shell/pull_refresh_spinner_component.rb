# frozen_string_literal: true

module Pito
  module Shell
    # The bottom pull-to-refresh spinner — Brave's top pull, inverted for pito's
    # bottom-anchored conversation. Ships as an inert <template> in the layout;
    # the pito--pull-refresh Stimulus controller clones it onto <body> on the
    # first upward pull, floats it up with the finger, and rotates the arrow
    # with the drag. Pure chrome: a Lucide refresh arrow on an elevated square
    # tile — no copy, never persisted, never visible outside a drag.
    class PullRefreshSpinnerComponent < ViewComponent::Base
      TEMPLATE_ID = "pito-pull-refresh-spinner"

      # Same gate as the refresh nudge: the scrollback is an authenticated
      # surface, and anonymous layouts stay free of chrome templates.
      def render?
        Current.session.present?
      end
    end
  end
end
