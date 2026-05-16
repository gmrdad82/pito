# Phase 27 v2 spec 02 — Collection composite cover rebuild orchestrator.
#
# Pure orchestrator. Sorts inputs deterministically (alphabetical by
# `Collection.name`, case-insensitive) and enqueues a sequential chain
# of `CollectionCoverRebuildJob` runs. The first job in the chain runs
# the first collection; on success it enqueues the next; and so on.
#
# Deterministic alphabetical ordering is load-bearing:
#   - UX — the user can SEE which collection is rebuilding next.
#   - Tests — assertions on enqueue order are stable.
#
# Public API:
#
#   queue = Collections::CompositeRebuildQueue.new
#   queue.enqueue_for_collections(collections)        # generic entry point
#   queue.enqueue_for_game_resync(game)               # walks game.collections
#   queue.enqueue_for_game_destroy(game, was_in: [c]) # explicit pre-destroy set
#
# Returns the array of collection ids enqueued (in the order they will
# process) so callers can assert on it.
#
# Sequential chain pattern:
#   - The orchestrator enqueues ONE `CollectionCoverRebuildJob` with two
#     args: `(head_collection_id, tail_ids)`. Each job, on success,
#     pops the head off `tail_ids` and enqueues the next run with the
#     remaining tail. When `tail_ids` is empty, the chain terminates.
#   - Sidekiq OSS does not have built-in unique jobs; the orchestrator
#     deduplicates the INPUT set so a single batch never enqueues the
#     same collection twice. Concurrent batches may still overlap, but
#     each job is idempotent (cache hit → no-op; cache miss → rebuild)
#     so the worst-case duplicate is one extra fingerprint check.
module Collections
  class CompositeRebuildQueue
    # Enqueue a sequential rebuild chain for the given collections.
    # `collections` accepts ActiveRecord relations, arrays, or any
    # enumerable of `Collection` instances. Returns the ordered array
    # of collection ids that will be processed (alphabetical by name,
    # case-insensitive, deduped). Empty input enqueues nothing.
    def enqueue_for_collections(collections)
      ids = sort_and_dedupe(collections)
      enqueue_chain(ids)
      ids
    end

    # Enqueue a rebuild chain for every collection the game currently
    # belongs to. Returns the ordered id list. When the game belongs to
    # zero collections, enqueues nothing.
    def enqueue_for_game_resync(game)
      enqueue_for_collections(Array(game&.collection).compact)
    end

    # Enqueue a rebuild chain for the collections a game WAS in before
    # destruction. The caller is expected to capture the pre-destroy
    # set (e.g. via `before_destroy`) since `after_destroy_commit` runs
    # after the row is gone and the FK is nullified.
    def enqueue_for_game_destroy(game, was_in:)
      _ = game # signature parity with enqueue_for_game_resync
      enqueue_for_collections(Array(was_in).compact)
    end

    private

    # Sort by `LOWER(name)` for case-insensitive alphabetical order;
    # dedupe by id (a single batch never enqueues the same collection
    # twice, even if the input set repeats it). Returns the ordered id
    # list.
    def sort_and_dedupe(collections)
      Array(collections)
        .compact
        .uniq(&:id)
        .sort_by { |c| c.name.to_s.downcase }
        .map(&:id)
    end

    # Enqueue the head of the chain. `ids` is the full ordered list;
    # the head runs first and carries the tail forward. Empty input
    # is a no-op.
    def enqueue_chain(ids)
      return if ids.empty?
      head, *tail = ids
      CollectionCoverRebuildJob.perform_async(head, tail)
    end
  end
end
