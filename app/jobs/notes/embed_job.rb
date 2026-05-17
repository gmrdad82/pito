# Phase 34 (2026-05-18) — Notes no longer participate in the unified
# `/games` Meilisearch corpus. The job is now a no-op; the call site
# in `NoteSyncJob#enqueue_embed` is kept (in case the corpus design
# reverts), but every `perform` short-circuits without an HTTP call.
#
# What changed:
#   - No Voyage AI HTTP call. The `notes.embedding` pgvector column
#     is left in place (no migration to drop) but receives no new
#     writes from this path. Existing values stay.
#   - No Meilisearch upsert. The previous `notes_<env>` index is
#     left to drift stale (no writes, no destroys); the physical
#     index can be deleted out-of-band when the operator notices it.
#
# Historical context (pre-Phase 34): the job dual-wrote a Voyage
# embedding to `notes.embedding` and to a `notes_<env>` Meilisearch
# index (BM25 + vector). The unified `/games` corpus introduced in
# Phase 34 collapses search down to Game + Bundle only — notes and
# videos no longer have a destination index.
module Notes
  class EmbedJob
    include Sidekiq::Job
    sidekiq_options queue: "search", retry: 3

    def perform(_note_id)
      # No-op. See file header.
    end
  end
end
