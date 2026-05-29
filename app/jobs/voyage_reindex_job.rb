# FB-63 (2026-05-20) — Voyage AI reindex job.
# R1 (2026-05-25) — bundle corpus removed; games only.
#
# Three-layer lock contract (unchanged from `ReindexAllJob`):
#
#   Layer 1 — DB flag (`AppSetting.reindex_running` +
#             `reindex_started_at`). The controller
#             (`SettingsController#voyage_reindex`) consults the flag
#             BEFORE enqueueing; this job's `ensure` block clears it
#             so a worker crash never leaves it stuck.
#   Layer 2 — unique-job lock (`lock: :until_executed`).
#   Layer 3 — UI gate (Voyage section + Stack pane shared running
#             state).
#
# Voyage rate-limit shape. Voyage's `/v1/embeddings` accepts up to 128
# input strings per request; one bulk job per corpus collapses N HTTP
# calls into ceil(N / 128).
#
# `REINDEX_SLEEP_SECONDS` preserves the testing-visibility pause from
# the prior `ReindexAllJob` so the operator can SEE the in-progress UI
# state before the flag clears. Dial down to `0` before any production
# use; leaving it at `8` in production would needlessly stall the
# queue.
class VoyageReindexJob < ApplicationJob
  REINDEX_SLEEP_SECONDS = 8

  queue_as :search

  def perform
    sleep REINDEX_SLEEP_SECONDS if REINDEX_SLEEP_SECONDS.positive?
    BulkVoyageIndexJob.perform_later(corpus: "games")
  ensure
    AppSetting.clear_reindex_lock!
  end
end
