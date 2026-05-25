module Pito
  # ADR 0018 — Action bus + cable architecture.
  #
  # Canonical entry point for every cable broadcast in pito. Enforces
  # the ADR 0017 envelope (`{ kind, payload, ts }`) and the
  # `pito:<screen>:<panel>[:<sub-panel>]` channel grammar so consumers
  # can never broadcast a raw shape or invent a non-pito channel name.
  #
  # Surfaces:
  #
  #   `.broadcast_status_bar(payload)` — global TST channel. Always
  #     `kind: "data"`; payload carries `sync_state`, `busy`, Sidekiq
  #     counters, clock.
  #
  #   `.broadcast_panel(channel, kind:, payload:)` — any panel- or
  #     sub-panel-scoped channel matching the `pito:` grammar. Caller
  #     specifies the kind (`indeterminate`, `progress`, `complete`,
  #     `error`, `reindex_event`, …).
  #
  #   `.broadcast_pause(target:, paused:)` — convenience wrapper that
  #     emits `kind: "pause"` on the given `target` stream (must start
  #     with `pito:`). Payload shape:
  #       `{ target: <String>, paused: <Boolean>, ts: <ISO8601> }`
  #     Honors the sync-enabled gate — suppressed when target or any
  #     ancestor is disabled.
  #
  #   `.broadcast_uncertain(target:, reason:)` — convenience wrapper
  #     that emits `kind: "uncertain"` on the given `target` stream
  #     (must start with `pito:`). Payload shape:
  #       `{ target: <String>, uncertain: true, reason: <String>, ts: <ISO8601> }`
  #     Honors the sync-enabled gate — suppressed when target or any
  #     ancestor is disabled.
  #
  #   `.broadcast_sync_state(target:, enabled:)` — sync-state toggle
  #     broadcast on `pito:sync_state`. Clients re-paint sync indicator
  #     glyphs from `{ target, enabled }`.
  #
  # Canonical kinds (all panel-scoped streams):
  #   indeterminate, progress, complete, error, reindex_event,
  #   pause, uncertain
  module CableBroadcaster
    extend self

    STATUS_BAR_CHANNEL = "pito:status_bar".freeze
    SYNC_STATE_CHANNEL = "pito:sync_state".freeze

    # `kind:` is optional and defaults to `"data"` so the existing
    # Sidekiq middleware + StackStatsBroadcastJob keep their original
    # call shape (`broadcast_status_bar(payload)`). FB-test-infra
    # (2026-05-22) added the `kind:` kwarg so the dev/test rake
    # surface (`bundle exec rake pito:test:broadcast_*`) can broadcast
    # synthetic envelopes with arbitrary kinds (`sidekiq`,
    # `notifications`, …) without inventing a sibling broadcaster.
    def broadcast_status_bar(payload, kind: "data")
      ActionCable.server.broadcast(
        STATUS_BAR_CHANNEL,
        { kind: kind.to_s, payload: payload, ts: Time.current.iso8601 }
      )
    end

    # 2026-05-25 (sync-rebuild) — server-side sync-state gate.
    #
    # `broadcast_panel` now consults the AppSetting-backed sync state
    # before fanning out a panel envelope. The cable suppression logic
    # used to live in the JS controller (`isTargetSyncDisabled` reading
    # `localStorage`); that source-of-truth split was the root cause of
    # every drift bug. With the gate planted here, the server is the
    # ONLY decider — disabled targets never reach any client.
    #
    # The channel name is parsed back into a sync target: every
    # `pito:<screen>:<panel>[:<sub_panel>]` channel maps to the
    # `<screen>.<panel>[.<sub_panel>]` target string used by
    # `Pito::SyncTargets`. The suppression chain (self → parent panel →
    # "app") is walked via `AppSetting.sync_enabled?`; if any link is
    # "no", the broadcast is dropped silently.
    def broadcast_panel(channel, kind:, payload:)
      raise ArgumentError, "channel must start with pito:" unless channel.to_s.start_with?("pito:")
      return if panel_sync_disabled?(channel)
      ActionCable.server.broadcast(
        channel,
        { kind: kind, payload: payload, ts: Time.current.iso8601 }
      )
    end

    # Emits a `pause` envelope on the target stream.
    #
    # Use when a background job or real-time process is temporarily
    # paused (e.g. a sync loop waiting for rate-limit headroom).
    # The caller decides the boolean semantics of `paused:`.
    #
    # Payload: `{ target:, paused:, ts: }`.
    # Honors the sync-enabled gate (dropped when target or ancestor is
    # disabled).
    def broadcast_pause(target:, paused:)
      broadcast_panel(
        target.to_s,
        kind: "pause",
        payload: { target: target.to_s, paused: !!paused, ts: Time.current.iso8601 }
      )
    end

    # Emits an `uncertain` envelope on the target stream.
    #
    # Use when the state of a remote resource cannot be confidently
    # determined (e.g. an API timeout, an ambiguous diff result). The
    # `reason:` string is a short, user-facing hint surfaced by the JS
    # panel controller.
    #
    # Payload: `{ target:, uncertain: true, reason:, ts: }`.
    # Honors the sync-enabled gate (dropped when target or ancestor is
    # disabled).
    def broadcast_uncertain(target:, reason:)
      broadcast_panel(
        target.to_s,
        kind: "uncertain",
        payload: { target: target.to_s, uncertain: true, reason: reason.to_s, ts: Time.current.iso8601 }
      )
    end

    # Sync-state envelope (sent once per cascaded target by
    # `SyncController#toggle`). All clients listen on
    # `pito:sync_state`; the JS sync-indicator controllers re-paint
    # their glyphs from the `{ target, enabled }` payload.
    def broadcast_sync_state(target:, enabled:)
      ActionCable.server.broadcast(
        SYNC_STATE_CHANNEL,
        {
          kind: "sync_state",
          payload: { target: target.to_s, enabled: !!enabled },
          ts: Time.current.iso8601
        }
      )
    end

    private

    # True when the channel's matching sync target (or any ancestor in
    # the suppression chain) is currently disabled. Returns false when
    # the channel parses cleanly but the target is not in the registry
    # (defensive — the broadcast still fires; the consumer panel just
    # is not gated).
    def panel_sync_disabled?(channel)
      target = channel_to_target(channel)
      return false if target.nil?
      chain = Pito::SyncTargets.suppression_chain(target)
      return false if chain.nil?
      chain.any? { |t| !AppSetting.sync_enabled?(t) }
    end

    # Parses `pito:home:stack:meilisearch` → `"home.stack.meilisearch"`.
    # Returns nil for non-conforming channels (e.g. legacy
    # `pito:settings:*` strings) so the gate is a no-op for them.
    def channel_to_target(channel)
      parts = channel.to_s.split(":")
      return nil unless parts.first == "pito"
      return nil if parts.length < 3
      screen = parts[1]
      return nil unless Pito::SyncTargets::PANELS_BY_SCREEN.key?(screen)
      parts.drop(1).join(".")
    end
  end
end
