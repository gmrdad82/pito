# FB-63 (2026-05-20) — Voyage AI-only reindex job.
#
# Half of the split that replaced the combined `ReindexAllJob`. Where
# `MeilisearchReindexJob` (its sibling) repushes the Game corpus into
# Meilisearch, this job re-embeds the SAME corpus through Voyage AI.
# R1 (2026-05-25) — bundle corpus removed; games only. The two jobs are independently triggerable from the Stack
# pane — each subsystem tile owns its own `[reindex]` action so the
# operator can refresh Voyage embeddings without burning Meilisearch
# work (or vice versa).
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
# calls into ceil(N / 128). The work itself runs in
# `BulkVoyageIndexJob` (preserved from the prior pipeline) — that
# class also writes the Meilisearch document with the freshly-computed
# `_vectors.default` so a Voyage-only reindex keeps the search index
# documents up to date too. See `BulkVoyageIndexJob` for the
# text-building contract that mirrors the single-record indexers.
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
    # ADR 0018 — panel-scoped cable broadcast. See `MeilisearchReindexJob`
    # for the rationale; this job mirrors the same `running` / `complete`
    # shape against its own `pito:settings:stack:voyage` channel.
    Pito::CableBroadcaster.broadcast_panel(
      "pito:settings:stack:voyage",
      kind: "reindex_event",
      payload: { state: "running" }
    )

    sleep REINDEX_SLEEP_SECONDS if REINDEX_SLEEP_SECONDS.positive?

    BulkVoyageIndexJob.perform_later(corpus: "games")
  ensure
    AppSetting.clear_reindex_lock!
    broadcast_voyage_section
    Pito::CableBroadcaster.broadcast_panel(
      "pito:settings:stack:voyage",
      kind: "reindex_event",
      payload: { state: "complete" }
    )
  end

  private

  def broadcast_voyage_section
    Turbo::StreamsChannel.broadcast_replace_to(
      "reindex_status",
      target: "voyage_section",
      partial: "settings/voyage_section"
    )
  rescue StandardError
    nil
  end
end
