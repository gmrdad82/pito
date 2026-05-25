module Pito
  # Pito::SyncState — single source of truth for the master sync pause.
  #
  # 2026-05-25 (collapse-to-master) — simplified from the per-target cascade
  # model to a single master boolean. Only one sync indicator exists in the
  # UI: the master `[ ] sync` in TST. Cable broadcasts are orthogonal —
  # panels still receive updates; they just no longer carry their own pause.
  #
  # ## Vocabulary
  #
  # * **disabled**  — the user has turned sync OFF via the `[x] sync` /
  #   `[ ] sync` toggle (`AppSetting.sync_enabled?("app")` = "no").
  #   Controlled by `SyncController#toggle`.
  #
  # * **paused**    — the user has explicitly paused all sync via the TST
  #   master indicator. Stored as `AppSetting.singleton_row.master_sync_paused`
  #   (boolean column). Background jobs and cable broadcasts are suppressed
  #   until resumed.
  #
  # ## Public API
  #
  #   Pito::SyncState.master_paused?   → Boolean
  #   Pito::SyncState.pause_master!    → broadcasts, persists
  #   Pito::SyncState.resume_master!   → broadcasts, persists
  #
  # ## Cable channel
  #
  # pause_master! / resume_master! broadcast on `"pito:status_bar"` — the
  # global TST stream — because the master sync indicator lives there.
  #
  # @contract see docs/architecture.md § Cable channel grammar
  module SyncState
    extend self

    MASTER_CABLE_CHANNEL = "pito:status_bar".freeze

    # Returns true when the master sync is currently paused by the user.
    def master_paused?
      AppSetting.master_sync_paused?
    end

    # Pauses all sync. Persists the flag and broadcasts `kind: "pause"` on
    # the global TST channel so every connected client repaints the master
    # sync indicator.
    def pause_master!
      AppSetting.pause_master!
      Pito::CableBroadcaster.broadcast_pause(
        target: MASTER_CABLE_CHANNEL,
        paused: true
      )
    end

    # Resumes all sync. Persists the flag and broadcasts `kind: "pause"`
    # with `paused: false` on the global TST channel.
    def resume_master!
      AppSetting.resume_master!
      Pito::CableBroadcaster.broadcast_pause(
        target: MASTER_CABLE_CHANNEL,
        paused: false
      )
    end

    # Returns the current master sync state:
    #   :paused  — master is paused.
    #   :syncing — master is active (enabled + unpaused).
    def state
      master_paused? ? :paused : :syncing
    end
  end
end
