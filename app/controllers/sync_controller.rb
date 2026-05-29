# SyncController — server-side sync-enabled toggle endpoint.
#
# Z2e (2026-05-25) — pause / resume actions removed alongside
# Pito::SyncState + Pito::SyncTargets (the multi-state sync machine is gone).
# The 3-state indicator (synced / syncing / disconnected) is pure JS; no
# server-side pause state is needed.
#
# The toggle endpoint is retained for AppSetting sync-enabled rows (the
# per-panel disable/enable gate that controls whether cable broadcasts fire
# at all). It uses a simple allowlist instead of the deleted SyncTargets
# service.
#
# All actions are cookie-authed via `Sessions::AuthConcern` (inherited from
# `ApplicationController`). Return `head :no_content` — Turbo-friendly; the
# UI updates via the cable broadcast.
class SyncController < ApplicationController
  ALLOWED_TARGETS = %w[app home home.stack home.stack.meilisearch home.stack.voyage
                        home.stack.postgres home.stack.assets].freeze

  def toggle
    target = params[:target].to_s
    return head :not_found unless ALLOWED_TARGETS.include?(target)

    next_enabled = !AppSetting.sync_enabled?(target)
    AppSetting.set_sync(target, next_enabled)
    Pito::CableBroadcaster.broadcast_sync_state(target: target, enabled: next_enabled)

    head :no_content
  end
end
