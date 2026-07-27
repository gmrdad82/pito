# frozen_string_literal: true

module Pito
  module Shell
    # The refresh nudge — ephemeral chrome cloned into the scrollback by
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

      # Anonymous pages carry NOTHING of the nudge: the check endpoint 401s
      # for them anyway, and the layout must stay free of scrollback-shaped
      # markup (.pito-turn) for unauthenticated visitors — the anonymous-leak
      # guard in conversations_spec pins that.
      def render?
        Current.session.present?
      end

      def text
        Pito::Copy.render("pito.copy.refresh_nudge.lines", combo: combo)
      end

      # The reload affordance, by platform: touch devices (the Android
      # shell has no keyboard and no refresh button — pull-to-refresh is
      # deliberately OFF) get "Tap here" (the nudge itself is tappable);
      # everyone else — Mac included — gets Ctrl+R (F5 lives too). Owner
      # 2026-07-24: the Mac cmd-swap DISPLAY is retired app-wide, so this no
      # longer sniffs for Mac to show ⌘R; the combo is Ctrl-based for every
      # keyboard, regardless of the OS actually bound to Cmd+R.
      def combo
        touch? ? "Tap here" : "Ctrl+R (or F5)"
      end

      private

      def touch?
        helpers.request.user_agent.to_s.match?(/Android|iPhone|iPad|Mobile/)
      end
    end
  end
end
