module Pito
  # Pito::SyncStateChannel — global broadcast channel for sync-state
  # changes.
  #
  # 2026-05-25 (sync-rebuild) — when the user toggles any sync target
  # (via the per-panel sync VC, the `Space s` master leader entry, or
  # the `sync_toggle` palette action), the server writes the cascade
  # to AppSetting AND broadcasts ONE envelope per cascaded target on
  # this channel. Every connected client subscribes once on layout
  # load; the JS sync-indicator controllers re-paint their glyphs from
  # the broadcast detail.
  #
  # The channel is install-wide (single broadcasting), mirroring
  # `StatusBarChannel`. Pito is single-install / multi-user (ADR
  # 0003); the auth gate rejects unauthenticated subscriptions but
  # does NOT scope the stream per user.
  #
  # Wire shape (broadcast envelope, per `Pito::CableBroadcaster`):
  #
  #   { kind: "sync_state",
  #     payload: { target: "home.stack.meilisearch", enabled: true },
  #     ts: "2026-05-25T12:34:56+00:00" }
  #
  # @contract see docs/architecture.md § Cable channel grammar
  class SyncStateChannel < ApplicationCable::Channel
    BROADCAST_NAME = "pito:sync_state".freeze

    def subscribed
      return reject unless current_user.present?

      stream_from BROADCAST_NAME
    end

    def unsubscribed
      stop_all_streams
    end
  end
end
