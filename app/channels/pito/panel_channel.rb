module Pito
  # Pito::PanelChannel — parameterized ActionCable channel for panel-scoped
  # subscriptions. ONE channel class handles all `pito:<screen>:<panel>`
  # streams via subscription params, so we avoid per-panel channel-class
  # proliferation as the dashboard grows.
  #
  # Subscription (JS side):
  #
  #   consumer.subscriptions.create(
  #     { channel: "Pito::PanelChannel", screen: "home", name: "security" },
  #     { received: (data) => { ... } }
  #   )
  #
  # Backend broadcast (Ruby side):
  #
  #   Pito::CableBroadcaster.broadcast_panel(
  #     "pito:home:security",
  #     kind: :sessions,
  #     payload: { ... }
  #   )
  #
  # Auth: `ApplicationCable::Connection` identifies by `current_user`, so we
  # reject subscriptions when no user is attached (belt-and-braces guard
  # mirroring StatusBarChannel).
  #
  # Allowlists: screen and panel names are explicitly enumerated. New panels
  # added to the dashboard MUST extend ALLOWED_PANELS — the regex guard is a
  # second line of defense against arbitrary stream injection.
  #
  # Kind relay: this channel is KIND-AGNOSTIC. It streams every envelope
  # emitted by `Pito::CableBroadcaster` verbatim — no server-side kind
  # filtering is applied. The JS panel controller is responsible for routing
  # each envelope by `kind`. Canonical panel-scoped kinds include:
  #   indeterminate, progress, complete, error, reindex_event, pause, uncertain
  #
  # `pause`     — emitted by `.broadcast_pause`; payload `{ target, paused, ts }`.
  # `uncertain` — emitted by `.broadcast_uncertain`; payload `{ target, uncertain: true, reason, ts }`.
  #
  # @contract see docs/architecture.md § Cable channel grammar
  class PanelChannel < ApplicationCable::Channel
    ALLOWED_SCREENS = %w[home videos games].freeze
    ALLOWED_PANELS = %w[
      security
      notifications
      stack
      games_releasing
      notifications_feed
      calendar
    ].freeze

    def subscribed
      return reject unless current_user.present?

      screen = params[:screen].to_s
      name = params[:name].to_s

      return reject unless ALLOWED_SCREENS.include?(screen)
      return reject unless ALLOWED_PANELS.include?(name)
      return reject unless name.match?(/\A[a-z_]+\z/)

      stream_from "pito:#{screen}:#{name}"
    end

    def unsubscribed
      stop_all_streams
    end
  end
end
