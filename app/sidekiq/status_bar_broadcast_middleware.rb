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

  def call(_job_instance, _job_payload, _queue)
    yield
  ensure
    broadcast_stats
  end

  private

  def broadcast_stats
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    payload = {
      kind: "data",
      payload: {
        busy: stats.workers_size,
        enqueued: stats.enqueued,
        retry: stats.retry_size,
        scheduled: stats.scheduled_size
      },
      ts: Time.current.iso8601
    }
    ActionCable.server.broadcast(BROADCAST_NAME, payload)
  rescue StandardError => e
    Rails.logger.warn("StatusBarBroadcastMiddleware failed: #{e.message}")
  end
end
