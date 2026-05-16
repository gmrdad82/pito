# Phase 27 v2 spec 01 — Single main genre per Game.
#
# Backfill `games.primary_genre_id` for every row that never had it
# computed. The column already exists in `db/schema.rb` (added in the
# 2026-05-11 Phase 27 follow-up — see `BetaMigration3`); the FK has
# `ON DELETE SET NULL`. This migration is data-only.
#
# Idempotent: a row with `primary_genre_id` already populated is left
# untouched. A row whose `game_genres` join is empty stays `NULL` (the
# UI renders that state as `"—"`). Re-running the migration is a no-op
# once every row is populated.
#
# Wrapped in `disable_ddl_transaction!` so the per-batch writes commit
# incrementally — a partial backfill on a large library can stop and
# resume without rolling back the whole sweep.
class BackfillGamesPrimaryGenre < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    picker = Games::PrimaryGenrePicker.new
    total  = 0

    Game.where(primary_genre_id: nil).find_each(batch_size: 500) do |game|
      genre = picker.pick(game)
      next if genre.nil?
      # `update_columns` bypasses callbacks AND validations (correct for
      # a backfill — the model `before_save :assign_primary_genre_if_blank`
      # hook would re-derive the same value, and we skip validations
      # because the row was already valid before the backfill).
      game.update_columns(primary_genre_id: genre.id)
      total += 1
    end

    say_with_time("backfilled primary_genre_id on #{total} games") { }
  end

  def down
    # Reversible: clear every populated pointer. The model
    # `before_save :assign_primary_genre_if_blank` hook re-derives on
    # the next save, and `Igdb::SyncGame#call` re-assigns on the next
    # sync — so a `db:rollback` followed by a fresh `db:migrate` is
    # idempotent. `in_batches.update_all` skips callbacks and runs as
    # a single UPDATE per batch (no per-row roundtrip).
    Game.where.not(primary_genre_id: nil)
        .in_batches(of: 500)
        .update_all(primary_genre_id: nil)
  end
end
