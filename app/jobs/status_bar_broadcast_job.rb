# FB-138 (2026-05-21). Trailing-edge broadcaster for the
# `pito:status_bar` cable channel that drives the Top Status Bar's
# `b<n> e<n> r<n>` queue-depth counters.
#
# Sibling of `StackStatsBroadcastJob` (which serves the
# `/settings` Stack pane). The two cover different channels but solve
# the same problem: the immediate broadcast fired from a worker's
# `ensure` block (here: `StatusBarBroadcastMiddleware#call`) still
# counts the calling worker in `Sidekiq::Stats.new.workers_size` /
# `Sidekiq::Workers.new.size` because the slot is released AFTER
# middleware return.
#
# Without this trailing-edge job the TST would freeze at `b1 e0 r0`
# after a reindex job finished — `b1` because the still-in-flight
# worker counted itself in the post-yield broadcast and no further
# broadcast ever fired.
#
# The middleware schedules this job with `set(wait: 1.second)` after
# every job completes. It runs in a fresh worker context AFTER the
# original worker decremented its busy counter, so its snapshot of
# `Sidekiq::Stats.new.workers_size` reflects reality. This job does
# NOT re-enqueue itself (it would loop forever).
#
# FB-171 (2026-05-21) — subtract 1 from `workers_size` because the
# trailing-edge job IS itself a Sidekiq worker. Without the subtract
# the broadcast reports `b1` (itself), which sticks on the TST until
# the next user-triggered job clears it. The job is intentionally
# the only thing in flight at this moment, so `workers_size - 1` is
# the post-completion truth for the previous real job.
class StatusBarBroadcastJob < ApplicationJob
  queue_as :default

  BROADCAST_NAME = "pito:status_bar".freeze

  def perform
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    busy = [ stats.workers_size - 1, 0 ].max
    payload = {
      kind: "data",
      payload: {
        busy: busy,
        enqueued: stats.enqueued,
        retry: stats.retry_size,
        scheduled: stats.scheduled_size,
        # FB-153 (2026-05-21). Mirror the middleware: every push carries
        # the shared reindex flag so the TST sync indicator flips back
        # to `synced` (●) when the trailing-edge broadcast lands after
        # a Voyage / Meilisearch reindex finishes.
        sync_state: reindex_running? ? "syncing" : "idle"
      },
      ts: Time.current.iso8601
    }
    ActionCable.server.broadcast(BROADCAST_NAME, payload)
  rescue StandardError => e
    Rails.logger.warn("StatusBarBroadcastJob failed: #{e.message}")
  end

  private

  def reindex_running?
    AppSetting.reindex_running?
  rescue StandardError
    false
  end
end
