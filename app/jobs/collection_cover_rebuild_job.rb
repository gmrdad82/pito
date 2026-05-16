# Phase 27 v2 spec 02 — Collection composite cover rebuild job.
#
# Rebuilds the on-disk composite for ONE collection, then enqueues the
# next job in the chain (if any). The orchestrator
# `Collections::CompositeRebuildQueue` builds the chain in alphabetical
# (by name) order; this job receives the head + tail explicitly and
# pops the head off the tail on success.
#
# Argument shape:
#   perform(collection_id)                — terminal (single rebuild, no chain).
#   perform(collection_id, [next, third]) — runs collection_id, then enqueues
#                                            the next job with [third].
#   perform(collection_id, nil)           — equivalent to passing [].
#
# Sidekiq runs in a separate process, so the in-memory `saved_changes`
# from the originating after_commit is gone by the time the job
# executes. The orchestrator passes ids explicitly.
#
# Sidekiq uniqueness — `lock: :until_executed` requires
# `sidekiq-unique-jobs` (OSS) or Sidekiq Enterprise. Pito uses neither;
# the options are recorded as no-op intent declarations (same pattern
# as `ReindexAllJob`). The orchestrator's per-batch dedupe is the real
# safety net.
#
# Failure semantics: if the composer raises, the chain BREAKS —
# remaining collections are NOT processed. The page-render path falls
# through to the synchronous-on-miss composer (the same surface that
# runs inline today on first miss). Letting Sidekiq retry the head
# would re-fire the whole chain tail on success; we want a hard stop so
# operator attention is required for the failing collection.
#
# Edge: when the collection was deleted between enqueue and run, the
# job no-ops gracefully (logs and returns) and STILL advances the chain
# — a deleted collection is not a "failure," just a moot rebuild.
class CollectionCoverRebuildJob
  include Sidekiq::Job
  sidekiq_options queue: :default, lock: :until_executed, on_conflict: :log

  def perform(collection_id, remaining_chain = nil)
    chain = Array(remaining_chain)

    rebuild_one(collection_id)

    # Only reached on a successful rebuild (or a graceful no-op for a
    # deleted collection). A composer raise propagates UP and skips
    # this enqueue, breaking the chain by design.
    enqueue_next(chain)
  end

  private

  # Look up the collection, run the composer. The composer is
  # internally idempotent (fingerprint hit → no-op, miss → rebuild).
  # A missing collection (deleted mid-flight) is a no-op WITHOUT a
  # raise — it must not strand the chain.
  def rebuild_one(collection_id)
    collection = Collection.find_by(id: collection_id)
    return if collection.nil?

    Collections::CoverComposer.new.call(collection)
  end

  # Pop the next id off `chain` and enqueue a fresh run with the tail.
  # No-op when the chain is empty. Reached only after a successful
  # rebuild — a raise inside `rebuild_one` skips this method so Sidekiq
  # retries the head without re-firing the tail.
  def enqueue_next(chain)
    return if chain.empty?
    head, *tail = chain
    self.class.perform_async(head, tail)
  end
end
