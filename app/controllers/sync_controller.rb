# SyncController — the single mutation endpoint for the server-side
# sync state.
#
# 2026-05-25 (sync-rebuild) — replaces every `localStorage.setItem`
# / `localStorage.getItem` call in the JS layer. The toggle handler
# walks `Pito::SyncTargets.cascade_targets(target)`, writes the same
# new value to every cascaded AppSetting row, and broadcasts ONE
# envelope per cascaded target on `pito:sync_state` so every connected
# client repaints in lockstep.
#
# Single action: `POST /sync/toggle?target=<target>`. The `target`
# param is allowlisted via `Pito::SyncTargets.valid?`; anything else
# 404s.
#
# Cookie-authed via `Sessions::AuthConcern` (inherited from
# `ApplicationController`). Returns `head :no_content` — Turbo-friendly,
# the UI updates via the cable broadcast.
class SyncController < ApplicationController
  def toggle
    target = params[:target].to_s
    return head :not_found unless Pito::SyncTargets.valid?(target)

    next_enabled = !AppSetting.sync_enabled?(target)
    cascade = Pito::SyncTargets.cascade_targets(target)

    cascade.each do |t|
      AppSetting.set_sync(t, next_enabled)
      Pito::CableBroadcaster.broadcast_sync_state(target: t, enabled: next_enabled)
    end

    head :no_content
  end
end
