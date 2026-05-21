# Phase 14 §1 — Sidekiq job wrapping `Game::Igdb::SyncGame#call`.
#
# Single argument `game_id`. On `Game::Igdb::Client::RateLimited` /
# `ServerError` / network errors, raises so Sidekiq retries with
# exponential backoff (5 attempts). On `ValidationError` (game ID
# does not exist on IGDB) the local row is stamped with
# `last_sync_error` inside `Game::Igdb::SyncGame` and the job swallows
# the raise so Sidekiq does NOT retry.
#
# Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
# The job flips `resyncing` true at start (skips when already in
# flight, so duplicate enqueues are no-ops) and back to false in
# an `ensure` block so a crash inside `SyncGame` still releases
# the lock.
#
# Phase 27 v2 spec 03 — two-layer lock + collection fan-out, mirroring
# `ReindexAllJob`'s pattern:
#
#   Layer 1 — DB mutex (`games.resyncing` Boolean). Set at start,
#             cleared in `ensure`. The controller consults the same
#             flag to short-circuit duplicate enqueues from the
#             breadcrumb [sync] click.
#   Layer 2 — Sidekiq uniqueness lock (`sidekiq_options lock:
#             :until_executed, on_conflict: :log`). Pito runs on
#             Sidekiq OSS without `sidekiq-unique-jobs`, so the
#             option is a NO-OP intent declaration today — the DB
#             flag (Layer 1) is the real safety net. If the gem is
#             ever added, the keys are already in place.
#
# UI feedback while a resync is in flight is handled entirely on
# `/games/:id` by the page-level `auto-refresh` controller (reloads
# every ~5 s while `@game.resyncing?` is true). The dedicated sync
# pane / banner and the `_sync_status` partial were removed —
# breadcrumb [sync] (muted-while-syncing per Wave C8) is the only
# control surface.
#
# Bundle cover-art fan-out (success path only) — every bundle the
# game belongs to gets its composite cover rebuilt via
# `Bundle::CompositeRebuildQueue#enqueue_for_game_resync`. The
# orchestrator alphabetizes and enqueues a sequential
# `BundleCoverBuild` chain so the UX (and the test suite) sees a
# predictable order. We call the orchestrator EXPLICITLY here even
# though the model's `after_save_commit
# :rebuild_bundle_composites_on_resync` hook also fires — the
# explicit call is the canonical spec-03 trigger (and the composer
# is idempotent on cache hit, so a duplicate enqueue is a no-op
# rebuild).
class GameIgdbSync
  include Sidekiq::Job
  sidekiq_options queue: :default,
                  retry: 5,
                  lock: :until_executed,
                  on_conflict: :log

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    # 2026-05-18 — controller-owned mutex flip. `GamesController#resync`
    # stamps `resyncing = true` SYNCHRONOUSLY before enqueuing the job
    # so the post-POST redirect renders the muted breadcrumb + auto-
    # refresh polling immediately (no race against Sidekiq pickup).
    # `update_column` skips validations / callbacks so this is safe to
    # call when the controller already set the flag (idempotent no-op).
    # The legacy `return if game.resyncing?` early-bail was retired in
    # lockstep — the controller now owns the gate (it short-circuits
    # duplicate user clicks with the "already resyncing." flash), and
    # console / rake callers that bypass the controller still get a
    # full sync because the job unconditionally flips the flag and runs.
    game.update_column(:resyncing, true)
    success = false
    begin
      Game::Igdb::SyncGame.new.call(game)
      success = true
    rescue Game::Igdb::Client::RateLimited => e
      sleep(e.retry_after.to_i.clamp(1, 60))
      raise
    rescue Game::Igdb::Client::ValidationError
      # Local row already stamped with last_sync_error inside SyncGame.
      # No re-raise — non-retryable. No bundle rebuild fan-out
      # (no data changed; nothing to rebuild).
      nil
    ensure
      # Phase 27 v2 spec 03 — success-path bundle cover-art fan-out.
      # Lives in the ensure block but gated on `success` so retryable /
      # non-retryable errors do not enqueue rebuilds. The fan-out runs
      # BEFORE the `resyncing` flip so the composite rebuilds always
      # read the freshly-resynced row (e.g. the new `cover_image_id`).
      if success
        begin
          Bundle::CompositeRebuildQueue.new
                                        .enqueue_for_game_resync(game.reload)
        rescue StandardError
          # Fan-out is a downstream nicety; a Bundle lookup failure or
          # Redis hiccup must not leak out of `ensure` and trip Sidekiq
          # retry on an already-successful sync.
          nil
        end
      end
      # Re-load to clear the flag even if the inner update! mutated
      # other columns; `update_column` works on the persisted record
      # regardless of the in-memory state.
      Game.where(id: game.id).update_all(resyncing: false)
    end
  end
end
