# frozen_string_literal: true

module Pito
  module Shell
    # The refresh nudge (G71) — ephemeral chrome cloned into the scrollback by
    # pito--cable-health when a cable RECONNECT reveals the server now runs a
    # NEWER version than this page (fresh CSS/JS the open tab won't get until
    # a real reload). Ships as a <template> in the layout: the copy is resolved
    # server-side at page render (all user-facing strings live in Pito::Copy),
    # with the reload combo picked for the visitor's OS from the User-Agent.
    # NEVER persisted — no Event row, no reply handle, nothing to share: a
    # yellow segment that exists only in the DOM of the tab it nudges and dies
    # with the reload it asks for.
    class RefreshNudgeComponent < ViewComponent::Base
      TEMPLATE_ID = "pito-refresh-nudge"

      def text
        Pito::Copy.render("pito.copy.refresh_nudge.lines", combo: combo)
      end

      # ⌘R on Macs, Ctrl+R (F5 lives too) everywhere else — sniffed server-side
      # so the rendered string stays fully resolved from the dictionary.
      def combo
        mac? ? "⌘R" : "Ctrl+R (or F5)"
      end

      private

      def mac?
        helpers.request.user_agent.to_s.match?(/Mac OS X|Macintosh/)
      end
    end
  end
end
