# 2026-05-11 polish (Games list-mode bulk actions, Fix 5).
#
# Per-game sync job dispatched by `BulkSyncJob` via the convention
# `"#{target_type}Sync".safe_constantize` (i.e. when a BulkOperationItem
# has `target_type: "Game"`, BulkSyncJob calls `GameSync.perform_async(id)`).
#
# Responsibilities:
#   - Acquire a Postgres advisory lock keyed on `(:game, game_id)` so
#     two concurrent jobs cannot operate on the same game row at
#     once. Other games still run in parallel — only the per-game
#     serialization is enforced. When the lock is unavailable (another
#     worker holds it), the job returns immediately; the in-flight
#     worker will complete the work.
#   - Delegate to `GameIgdbSync.new.perform(game_id)` which already
#     handles the `games.resyncing` mutex flag + IGDB sync via
#     `Game::Igdb::SyncGame#call`.
#   - Rescue StandardError so a single failure does not abort the
#     enclosing `BulkSyncJob` batch; the error is logged and the row's
#     `last_sync_error` column carries the message for surfaces that
#     read it.
#
class GameSync < ApplicationJob
  queue_as :default

  # Postgres advisory-lock classes are 32-bit signed ints. We pick a
  # fixed namespace integer per resource so the (namespace, id) pair
  # cannot collide with other advisory-lock users in the codebase.
  ADVISORY_LOCK_NAMESPACE = 7_001

  def perform(game_id)
    return unless game_id

    ActiveRecord::Base.connection.transaction do
      acquired = pg_try_advisory_xact_lock(ADVISORY_LOCK_NAMESPACE, game_id.to_i)
      unless acquired
        Rails.logger.info("[GameSync] game_id=#{game_id} advisory lock unavailable; another worker is syncing")
        next
      end

      run_sync(game_id)
    end
  end

  private

  def run_sync(game_id)
    GameIgdbSync.new.perform(game_id)
  rescue StandardError => e
    Rails.logger.error("[GameSync] game_id=#{game_id} failed: #{e.class}: #{e.message}")
    Game.where(id: game_id).update_all(
      last_sync_error: "#{e.class}: #{e.message[0, 240]}"
    )
    # Swallow so a per-game failure does not propagate up and crash
    # the enclosing BulkSyncJob batch.
    nil
  end

  def pg_try_advisory_xact_lock(namespace, key)
    sql = "SELECT pg_try_advisory_xact_lock(#{namespace.to_i}, #{key.to_i}) AS acquired"
    ActiveRecord::Base.connection.execute(sql).first["acquired"]
  end
end
