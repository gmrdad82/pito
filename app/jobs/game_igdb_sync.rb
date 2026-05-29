#
# Single argument `game_id`. On `Game::Igdb::Client::RateLimited` /
# `ServerError` / network errors, with
# exponential backoff (5 attempts). On `ValidationError` (game ID
# does not exist on IGDB) the local row is stamped with
# `last_sync_error` inside `Game::Igdb::SyncGame` and the job swallows
# the raise, not retrying.
#
# Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
# The job flips `resyncing` true at start (skips when already in
# flight, so duplicate enqueues are no-ops) and back to false in
# an `ensure` block so a crash inside `SyncGame` still releases
# the lock.
#
# Phase 27 v2 spec 03 — two-layer lock, mirroring `ReindexAllJob`'s pattern:
#
#   Layer 1 — DB mutex (`games.resyncing` Boolean). Set at start,
#             cleared in `ensure`. The controller consults the same
#             flag to short-circuit duplicate enqueues from the
#             breadcrumb [sync] click.
#
# UI feedback while a resync is in flight is handled entirely on
# `/games/:id` by the page-level `auto-refresh` controller (reloads
# every ~5 s while `@game.resyncing?` is true). The dedicated sync
# pane / banner and the `_sync_status` partial were removed —
# breadcrumb [sync] (muted-while-syncing per Wave C8) is the only
# control surface.
#
# R1 (2026-05-25) — bundle cover-art fan-out removed with bundles.
class GameIgdbSync < ApplicationJob
  queue_as :default

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    # 2026-05-18 — controller-owned mutex flip. `GamesController#resync`
    # stamps `resyncing = true` SYNCHRONOUSLY before enqueuing the job
    # so the post-POST redirect renders the muted breadcrumb + auto-
    # refresh polling immediately (no race condition).
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
      # No re-raise — non-retryable.
      nil
    ensure
      # Re-load to clear the flag even if the inner update! mutated
      # other columns; `update_column` works on the persisted record
      # regardless of the in-memory state.
      Game.where(id: game.id).update_all(resyncing: false)
    end
  end
end
