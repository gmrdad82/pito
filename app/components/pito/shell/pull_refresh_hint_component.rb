# frozen_string_literal: true

module Pito
  module Shell
    # The pull-to-refresh indicator (G81) — a shrug and one short ironic line,
    # revealed under the last message while the Android shell's bottom pull
    # (pito--pull-refresh) is in progress; flips to the armed color past the
    # reload threshold. Ships as an inert <template> in the layout so the copy
    # is server-resolved (Pito::Copy, 50 variants — one sampled per page);
    # never persisted, never visible outside a drag.
    class PullRefreshHintComponent < ViewComponent::Base
      TEMPLATE_ID = "pito-pull-refresh-hint"

      SHRUG = '¯\\_(ツ)_/¯'

      # Same gate as the refresh nudge: the scrollback is an authenticated
      # surface, and anonymous layouts stay free of chrome templates.
      def render?
        Current.session.present?
      end

      def text
        Pito::Copy.render("pito.copy.pull_refresh.hints")
      end
    end
  end
end
