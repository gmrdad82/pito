# 2026-05-18 (DR follow-up) — ActionCable channel that pushes
# `/settings` Stack-pane updates from Sidekiq jobs to every connected
# browser tab. Replaces the prior 3-second HTTP poll
# (`stack_stats_live_controller.js` -> `GET /settings/stack_stats`).
#
# Subscribers stream from the `stack_stats` broadcasting; producers
# are background jobs (Voyage indexers, ReindexAllJob) that call
# `StackStats::Broadcaster.broadcast!` at meaningful state-change
# moments. Connection authentication: enforced at the HTTP layer that
# serves `/settings` (Rails session `before_action` gates the page
# render). The ActionCable subscription itself has no per-user
# identification — `ApplicationCable::Connection` is an empty subclass
# with no `identified_by`. Pito is single-install, multi-user (ADR
# 0003), so channel-level scoping is unnecessary: every subscriber
# sees the same global Stack-pane snapshot.
class StackStatsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "stack_stats"
  end
end
