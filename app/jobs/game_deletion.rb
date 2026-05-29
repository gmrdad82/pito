# 2026-05-11 polish (Games list-mode bulk actions, Fix 5).
#
# Per-game deletion job. Dispatched by `BulkDeleteJob` when the
# operation's target_type is "Game" — the bulk job hands each row off

# rows, with per-row advisory locking to prevent two workers from
# operating on the same game.
#
# Responsibilities:
#   - Acquire a Postgres advisory lock keyed on `(:game, game_id)` so
#     two concurrent jobs cannot destroy / sync the same game row at
#     once. Releases automatically on the transaction's commit.
#   - `target.destroy` the game. The Game model handles its own
#     dependent: :destroy associations.
#   - Rescue StandardError + ActiveRecord::RecordNotFound so a single
#     failure does not abort the surrounding batch — the bulk operation
#     item is marked failed via Turbo-stream broadcast back to the
#     bulk operations channel.
class GameDeletion < ApplicationJob
  queue_as :bulk_deletion

  ADVISORY_LOCK_NAMESPACE = 7_002

  def perform(game_id, bulk_operation_item_id = nil)
    return unless game_id

    op_item = BulkOperationItem.find_by(id: bulk_operation_item_id) if bulk_operation_item_id

    ActiveRecord::Base.connection.transaction do
      acquired = pg_try_advisory_xact_lock(ADVISORY_LOCK_NAMESPACE, game_id.to_i)
      unless acquired
        Rails.logger.info("[GameDeletion] game_id=#{game_id} advisory lock unavailable; another worker is acting on this row")
        mark_failed(op_item, "advisory_lock_busy")
        next
      end

      run_deletion(game_id, op_item)
    end

    # Last-one-out finalization. Each per-row job pings the bulk
    # operation; the call is idempotent (re-flipping a terminal-state
    # operation is a no-op via the `completed_at.present?` guard).
    BulkDeleteJob.finalize_if_complete(op_item.bulk_operation_id) if op_item
  end

  private

  def run_deletion(game_id, op_item)
    game = Game.find_by(id: game_id)
    unless game
      mark_failed(op_item, "not_found")
      return
    end

    if game.destroy
      mark_succeeded(op_item)
    else
      mark_failed(op_item, game.errors.full_messages.join(", ").presence || "destroy_returned_false")
    end
  rescue StandardError => e
    Rails.logger.error("[GameDeletion] game_id=#{game_id} failed: #{e.class}: #{e.message}")
    mark_failed(op_item, "#{e.class}: #{e.message[0, 240]}")
    # Swallow — a per-game failure must not crash the wider batch.
    nil
  end

  def mark_succeeded(op_item)
    return unless op_item

    op_item.update!(status: :succeeded)
    broadcast(op_item, "succeeded")
  end

  def mark_failed(op_item, message)
    return unless op_item

    op_item.update!(status: :failed, error_message: message)
    broadcast(op_item, "failed")
  end

  def broadcast(op_item, status)
    Turbo::StreamsChannel.broadcast_replace_to(
      "bulk_operation_#{op_item.bulk_operation_id}",
      target: "item_status_#{op_item.id}",
      partial: "bulk_operations/item_row",
      locals: { item_id: op_item.id, status: status }
    )
  rescue StandardError => e
    # Broadcast failures are non-fatal — the DB row is the source of
    # truth; the UI rehydrates on the next poll if Turbo dropped a
    # frame.
    Rails.logger.warn("[GameDeletion] broadcast failed: #{e.class}: #{e.message}")
  end

  def pg_try_advisory_xact_lock(namespace, key)
    sql = "SELECT pg_try_advisory_xact_lock(#{namespace.to_i}, #{key.to_i}) AS acquired"
    ActiveRecord::Base.connection.execute(sql).first["acquired"]
  end
end
