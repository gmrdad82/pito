module Pito
  # ADR 0018 — Action bus + cable architecture.
  #
  # Canonical entry point for every cable broadcast in pito. Enforces
  # the ADR 0017 envelope (`{ kind, payload, ts }`) and the
  # `pito:<screen>:<panel>[:<sub-panel>]` channel grammar so consumers
  # can never broadcast a raw shape or invent a non-pito channel name.
  #
  # Two surfaces:
  #
  #   `.broadcast_status_bar(payload)` — global TST channel. Always
  #     `kind: "data"`; payload carries `sync_state`, `busy`, Sidekiq
  #     counters, clock.
  #
  #   `.broadcast_panel(channel, kind:, payload:)` — any panel- or
  #     sub-panel-scoped channel matching the `pito:` grammar. Caller
  #     specifies the kind (`indeterminate`, `progress`, `complete`,
  #     `error`, `reindex_event`, …).
  module CableBroadcaster
    extend self

    STATUS_BAR_CHANNEL = "pito:status_bar".freeze

    def broadcast_status_bar(payload)
      ActionCable.server.broadcast(
        STATUS_BAR_CHANNEL,
        kind: "data",
        payload: payload,
        ts: Time.current.iso8601
      )
    end

    def broadcast_panel(channel, kind:, payload:)
      raise ArgumentError, "channel must start with pito:" unless channel.to_s.start_with?("pito:")
      ActionCable.server.broadcast(
        channel,
        kind: kind,
        payload: payload,
        ts: Time.current.iso8601
      )
    end
  end
end
