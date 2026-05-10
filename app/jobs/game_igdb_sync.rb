# Phase 14 §1 — Sidekiq job wrapping `Igdb::SyncGame#call`.
#
# Single argument `game_id`. On `Igdb::Client::RateLimited` /
# `ServerError` / network errors, raises so Sidekiq retries with
# exponential backoff (5 attempts). On `ValidationError` (game ID
# does not exist on IGDB) the local row is stamped with
# `last_sync_error` inside `Igdb::SyncGame` and the job swallows
# the raise so Sidekiq does NOT retry.
class GameIgdbSync
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Igdb::SyncGame.new.call(game)
  rescue Igdb::Client::RateLimited => e
    sleep(e.retry_after.to_i.clamp(1, 60))
    raise
  rescue Igdb::Client::ValidationError
    # Local row already stamped with last_sync_error inside SyncGame.
    # No re-raise — non-retryable.
    nil
  end
end
