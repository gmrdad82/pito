# Phase 27 follow-up (2026-05-17) — Bundle composite cover rebuild
# orchestrator. Replaces the Phase 27 v2 spec 02
# `Collections::CompositeRebuildQueue` (Collection model removed in
# the 2026-05-17 simplification).
#
# Pure orchestrator. Sorts inputs deterministically (alphabetical by
# `Bundle.name`, case-insensitive) and enqueues a sequential chain of
# `BundleCoverBuild` runs. The first job runs the first bundle; on
# success it enqueues the next; and so on.
#
# Deterministic alphabetical ordering is load-bearing:
#   - UX — the user can SEE which bundle is rebuilding next.
#   - Tests — assertions on enqueue order are stable.
#
# Public API:
#
#   queue = Bundle::CompositeRebuildQueue.new
#   queue.enqueue_for_bundles(bundles)            # generic entry point
#   queue.enqueue_for_game_resync(game)           # walks game.bundles
#   queue.enqueue_for_game_destroy(game, was_in: [b]) # explicit pre-destroy set
#
# Returns the array of bundle ids enqueued (in the order they will
# process) so callers can assert on it.
#
# Sequential chain pattern:
#   - The orchestrator enqueues ONE `BundleCoverBuild` with two args:
#     `(head_bundle_id, tail_ids)`. Each job, on success, pops the
#     head off `tail_ids` and enqueues the next run with the remaining
#     tail. When `tail_ids` is empty, the chain terminates.
#   - The orchestrator deduplicates the INPUT set so a single batch
#     never enqueues the same bundle twice. Concurrent batches may
#     still overlap, but each job is idempotent (fingerprint hit →
#     no-op; miss → rebuild) so the worst-case duplicate is one extra
#     fingerprint check.
class Bundle
  class CompositeRebuildQueue
    # Enqueue a sequential rebuild chain for the given bundles.
    # `bundles` accepts ActiveRecord relations, arrays, or any
    # enumerable of `Bundle` instances. Returns the ordered array of
    # bundle ids that will be processed (alphabetical by name,
    # case-insensitive, deduped). Empty input enqueues nothing.
    def enqueue_for_bundles(bundles)
      ids = sort_and_dedupe(bundles)
      enqueue_chain(ids)
      ids
    end

    # Enqueue a rebuild chain for every bundle the game currently
    # belongs to. Returns the ordered id list. When the game belongs to
    # zero bundles, enqueues nothing.
    def enqueue_for_game_resync(game)
      enqueue_for_bundles(Array(game&.bundles).compact)
    end

    # Enqueue a rebuild chain for the bundles a game WAS in before
    # destruction. The caller is expected to capture the pre-destroy
    # set (e.g. via `before_destroy`) since `after_destroy_commit` runs
    # after the row is gone and the join rows have CASCADED away.
    def enqueue_for_game_destroy(game, was_in:)
      _ = game # signature parity with enqueue_for_game_resync
      enqueue_for_bundles(Array(was_in).compact)
    end

    private

    # Sort by `LOWER(name)` for case-insensitive alphabetical order;
    # dedupe by id (a single batch never enqueues the same bundle
    # twice, even if the input set repeats it). Returns the ordered id
    # list.
    def sort_and_dedupe(bundles)
      Array(bundles)
        .compact
        .uniq(&:id)
        .sort_by { |b| b.name.to_s.downcase }
        .map(&:id)
    end

    # Enqueue the head of the chain. `ids` is the full ordered list;
    # the head runs first and carries the tail forward. Empty input
    # is a no-op.
    def enqueue_chain(ids)
      return if ids.empty?
      head, *tail = ids
      BundleCoverBuild.perform_async(head, tail)
    end
  end
end
