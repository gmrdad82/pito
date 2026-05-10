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
class GameIgdbSync
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    # Mutex guard — bail out if another worker is already syncing
    # this game. `update_column` skips validations / callbacks so
    # the local-only column flip never collides with the IGDB
    # update! inside SyncGame.
    return if game.resyncing?

    game.update_column(:resyncing, true)
    begin
      Igdb::SyncGame.new.call(game)
    rescue Igdb::Client::RateLimited => e
      sleep(e.retry_after.to_i.clamp(1, 60))
      raise
    rescue Igdb::Client::ValidationError
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
