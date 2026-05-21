# Beta 4 — Phase F1 Lane A. Sidekiq server middleware that broadcasts
# queue-depth snapshots to `pito:status_bar` after every job runs.
#
# Mounted in `config/initializers/sidekiq.rb` via the
# `Sidekiq.configure_server` block. Server-side middleware (not client)
# because we want the broadcast to fire AFTER the job completes, when
# the queue depths actually reflect the post-job state.
#
# Wrapped in `ensure` so the broadcast still fires even when the job
# raises (the job's failure then surfaces in `retry` count on the next
# broadcast — useful TUI feedback). The `rescue StandardError` on
# `broadcast_stats` guards against transient ActionCable / Redis
# hiccups: a broken cable backend should NEVER swallow a real job
# failure or leak its own exception up the Sidekiq stack.
class StatusBarBroadcastMiddleware
  include Sidekiq::ServerMiddleware

  BROADCAST_NAME = "pito:status_bar".freeze

  # ActiveJob wraps every job inside Sidekiq's
  # `ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper`. The actual
  # job class lives in `job_payload["wrapped"]` (string) for ActiveJob,
  # while raw Sidekiq workers expose it in `job_payload["class"]`.
  # `current_job_class` returns the resolved class name so the
  # self-skip guard below works for both adapter shapes.
  ACTIVE_JOB_WRAPPER = "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper".freeze

  def call(_job_instance, job_payload, _queue)
    @current_job_class = resolve_job_class(job_payload)
    # FB-153 / FB-154 (2026-05-21). Without a START broadcast the TST
    # only ever receives the post-`ensure` snapshot, so the user sees
    # `b0 → b0` and never observes the `b1` mid-flight. Firing the
    # broadcast BEFORE `yield` paints the busy increment immediately
    # (the just-started worker is already counted in `workers_size`).
    # The trailing `StatusBarBroadcastJob` (scheduled in `ensure`)
    # still snaps the post-job state once Sidekiq releases the slot.
    # The self-skip guard prevents the trailing-edge job itself from
    # triggering yet another START broadcast / nested schedule.
    #
    # FB-171 (2026-05-21) — `resolve_job_class` now correctly unwraps
    # the ActiveJob `JobWrapper` so the self-skip guard fires when the
    # trailing-edge `StatusBarBroadcastJob` re-enters the middleware.
    # Before this fix the guard checked the wrapper class name and
    # NEVER matched, producing an infinite chain of trailing-edge
    # jobs every 1 second that kept `b1` stuck on the TST after a
    # reindex completed.
    broadcast_stats unless @current_job_class == "StatusBarBroadcastJob"
    yield
  ensure
    broadcast_stats
    schedule_trailing_broadcast
  end

  private

  # Resolve the actual job class from the Sidekiq job payload. For
  # ActiveJob the wrapper class is `JobWrapper` and the real class
  # name is stored in `wrapped`; for raw Sidekiq jobs the class name
  # is the top-level `class` field.
  def resolve_job_class(job_payload)
    return nil unless job_payload
    top = job_payload["class"]
    return job_payload["wrapped"] if top == ACTIVE_JOB_WRAPPER
    top
  end

  def broadcast_stats
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    # FB-171 (2026-05-21). When this middleware fires from inside the
    # trailing-edge `StatusBarBroadcastJob`'s own server-middleware
    # chain (the `ensure` branch — the self-skip guard above blocks
    # the pre-yield branch), `Sidekiq::Stats.new.workers_size` still
    # counts the trailing-edge worker itself. Subtract 1 in that case
    # so the TST `b<n>` cell snaps to 0 after the last real job
    # finishes instead of sticking at `b1` until the next user click.
    busy = stats.workers_size
    busy = [ busy - 1, 0 ].max if @current_job_class == "StatusBarBroadcastJob"
    payload = {
      kind: "data",
      payload: {
        busy: busy,
        enqueued: stats.enqueued,
        retry: stats.retry_size,
        scheduled: stats.scheduled_size,
        # FB-153 (2026-05-21). Carry the shared reindex lock on every
        # status-bar push so the TST's sync indicator (●/◐ + word)
        # tracks reindex job state. `kind: "data"` payloads now also
        # drive the sync dot color via this field — see the matching
        # block in `tui_status_bar_controller.js#applyPayload`.
        sync_state: reindex_running? ? "syncing" : "idle"
      },
      ts: Time.current.iso8601
    }
    ActionCable.server.broadcast(BROADCAST_NAME, payload)
  rescue StandardError => e
    Rails.logger.warn("StatusBarBroadcastMiddleware failed: #{e.message}")
  end

  def reindex_running?
    AppSetting.reindex_running?
  rescue StandardError
    false
  end

  # FB-138 (2026-05-21). The in-`ensure` broadcast above still counts
  # the current worker in `Sidekiq::Stats.new.workers_size` because
  # the slot release happens AFTER this middleware returns. Without a
  # follow-up broadcast the TST would stick at `b1 e0 r0` once the
  # last job finished. Mirroring `StackStatsBroadcastJob`'s pattern,
  # we schedule a one-shot trailing-edge broadcast 1 second out; by
  # then the worker has released its slot and the snapshot reflects
  # reality. The follow-up job does NOT re-enqueue itself, so this
  # only fires once per real job — no loop, no thrash.
  #
  # Self-skip: the trailing-edge job is itself a Sidekiq job and
  # therefore re-enters this middleware. Without a guard we'd queue
  # an infinite chain of trailing broadcasts. The class-name check
  # short-circuits cleanly without coupling either side to the other's
  # internals.
  #
  # FB-171 (2026-05-21) — `resolve_job_class` now correctly unwraps
  # the ActiveJob `JobWrapper`; before this fix the guard NEVER
  # matched and every trailing-edge job re-scheduled another, causing
  # an infinite chain of broadcasts that kept `b1` stuck.
  def schedule_trailing_broadcast
    return if @current_job_class == "StatusBarBroadcastJob"
    StatusBarBroadcastJob.set(wait: 1.second).perform_later
  rescue StandardError => e
    Rails.logger.warn("StatusBarBroadcastMiddleware trailing broadcast schedule failed: #{e.message}")
  end
end
