# 2026-05-18 (DR follow-up) — ActionCable channel that pushes
# `/settings` Stack-pane updates from Sidekiq jobs to every connected
# browser tab. Replaces the prior 3-second HTTP poll
# (`stack_stats_live_controller.js` -> `GET /settings/stack_stats`).
#
# Subscribers stream from the `stack_stats` broadcasting; producers
# are background jobs (Voyage indexers, ReindexAllJob) that call
# `StackStats::Broadcaster.broadcast!` at meaningful state-change
# moments. Connection auth piggybacks on the existing
# `ApplicationCable::Connection` identification (cookie-session based).
#
# Single-user app: no per-user scoping; every subscriber sees the
# same global Stack-pane snapshot. If pito ever grows multi-tenant,
# this channel will need a `verified_user`-scoped stream key.
class StackStatsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "stack_stats"
  end
end
