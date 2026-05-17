# Phase 14 §1 — Sidekiq job wrapping `Igdb::SyncGame#call`.
#
# Single argument `game_id`. On `Igdb::Client::RateLimited` /
# `ServerError` / network errors, raises so Sidekiq retries with
# exponential backoff (5 attempts). On `ValidationError` (game ID
# does not exist on IGDB) the local row is stamped with
# `last_sync_error` inside `Igdb::SyncGame` and the job swallows
# the raise so Sidekiq does NOT retry.
#
# Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
# The job flips `resyncing` true at start (skips when already in
# flight, so duplicate enqueues are no-ops) and back to false in
# an `ensure` block so a crash inside `SyncGame` still releases
# the lock.
#
# Phase 27 v2 spec 03 — three-layer lock + live UI + collection
# fan-out, mirroring `ReindexAllJob`'s pattern:
#
#   Layer 1 — DB mutex (`games.resyncing` Boolean). Set at start,
#             cleared in `ensure`. The controller consults the same
#             flag to short-circuit duplicate enqueues from the
#             [resync] click.
#   Layer 2 — Sidekiq uniqueness lock (`sidekiq_options lock:
#             :until_executed, on_conflict: :log`). Pito runs on
#             Sidekiq OSS without `sidekiq-unique-jobs`, so the
#             option is a NO-OP intent declaration today — the DB
#             flag (Layer 1) is the real safety net. If the gem is
#             ever added, the keys are already in place.
#   Layer 3 — UI gate. The show view renders `games/_sync_status`
#             — the dot-loader while `resyncing?`, the `[resync]`
#             button otherwise — and subscribes permanently to the
#             `"game_resync:<id>"` Turbo-Stream. The broadcast in
#             `broadcast_resync_state` fires twice per run (success
#             path before fan-out, and again in `ensure`) so any
#             open tab swaps to the latest state without a refresh.
#
# Collection cover-art fan-out (success path only) — every collection
# the game belongs to gets its composite cover rebuilt via
# `Collections::CompositeRebuildQueue#enqueue_for_game_resync`. The
# orchestrator alphabetizes and enqueues a sequential chain so the
# UX (and the test suite) sees a predictable order. We call the
# orchestrator EXPLICITLY here even though the model's
# `after_save_commit :rebuild_collection_composites_on_resync` hook
# also fires — the explicit call is the canonical spec-03 trigger
# (and `CollectionCoverRebuildJob` is idempotent on cache hit, so a
# duplicate enqueue is a no-op rebuild).
class GameIgdbSync
  include Sidekiq::Job
  sidekiq_options queue: :default,
                  retry: 5,
                  lock: :until_executed,
                  on_conflict: :log

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    # Mutex guard — bail out if another worker is already syncing
    # this game. `update_column` skips validations / callbacks so
    # the local-only column flip never collides with the IGDB
    # update! inside SyncGame.
    return if game.resyncing?

    game.update_column(:resyncing, true)
    success = false
    begin
      Igdb::SyncGame.new.call(game)
      success = true
    rescue Igdb::Client::RateLimited => e
      sleep(e.retry_after.to_i.clamp(1, 60))
      raise
    rescue Igdb::Client::ValidationError
      # Local row already stamped with last_sync_error inside SyncGame.
      # No re-raise — non-retryable. No collection rebuild fan-out
      # (no data changed; nothing to rebuild).
      nil
    ensure
      # Phase 27 v2 spec 03 — success-path collection cover-art
      # fan-out. Lives in the ensure block but gated on `success`
      # so retryable / non-retryable errors do not enqueue rebuilds.
      # The fan-out runs BEFORE the `resyncing` flip so the
      # composite rebuilds always read the freshly-resynced row
      # (e.g. the new `cover_image_id`).
      if success
        begin
          Collections::CompositeRebuildQueue.new
                                            .enqueue_for_game_resync(game.reload)
        rescue StandardError
          # Fan-out is a downstream nicety; a Collection lookup
          # failure or Redis hiccup must not leak out of `ensure`
          # and trip Sidekiq retry on an already-successful sync.
          nil
        end
      end
      # Re-load to clear the flag even if the inner update! mutated
      # other columns; `update_column` works on the persisted record
      # regardless of the in-memory state.
      Game.where(id: game.id).update_all(resyncing: false)
      broadcast_resync_state(game.id)
    end
  end

  private

  # Phase 27 v2 spec 03 — re-render the `games/_sync_status` partial
  # and replace the `game_sync_status_<id>` target on the
  # `"game_resync:<id>"` Turbo-Stream. The partial reads
  # `game.resyncing?` fresh, so post-clear it lands in the idle
  # `[resync]` state. A Redis / Turbo wire failure is swallowed —
  # the broadcast is a UX nicety, not a correctness requirement,
  # and a raise here would trip Sidekiq retry on an otherwise
  # successful run.
  def broadcast_resync_state(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Turbo::StreamsChannel.broadcast_replace_to(
      "game_resync:#{game.id}",
      target: "game_sync_status_#{game.id}",
      partial: "games/sync_status",
      locals: { game: game }
    )
  rescue StandardError
    nil
  end
end
