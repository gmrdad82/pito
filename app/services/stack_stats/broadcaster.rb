# 2026-05-18 (DR follow-up) — Push the live Stack-pane snapshot to
# every connected `/settings` tab over ActionCable. Called from
# Sidekiq jobs at meaningful state-change moments (Voyage indexers,
# `ReindexAllJob`) so the previous 3-second HTTP poll can be retired.
#
# Sidekiq queue counters (busy / scheduled / enqueued / retry / dead)
# trade-off: this broadcaster only fires when a job completes (or when
# `ReindexAllJob` enters / exits). It does NOT broadcast every second
# while a job is queued or running. The numbers therefore update at
# job-completion boundaries, not continuously. The reasoning: when no
# job is running, the counters are static; when a job IS running, the
# burst comes from a few-second event, then settles. The visible
# numbers reach steady-state immediately after the job ends. A
# periodic heartbeat job was rejected as overkill for a solo-user app.
#
# Broadcasting from a Sidekiq worker is supported by ActionCable —
# `ActionCable.server.broadcast` reaches the configured pubsub adapter
# (Redis in dev, SolidCable in prod), which fans out to every Puma
# process that has a subscriber. No special wiring needed.
module StackStats
  class Broadcaster
    BROADCASTING = "stack_stats"

    def self.broadcast!
      payload = StackStats::Payload.call
      ActionCable.server.broadcast(BROADCASTING, payload)
    rescue StandardError => e
      # Broadcasting is a UX nicety; a Redis hiccup or payload-build
      # failure must not raise out of the worker's ensure block.
      Rails.logger.warn("[StackStats::Broadcaster] #{e.class}: #{e.message}")
      nil
    end
  end
end
