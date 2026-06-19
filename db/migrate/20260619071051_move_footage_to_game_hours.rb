# frozen_string_literal: true

class MoveFootageToGameHours < ActiveRecord::Migration[8.1]
  # Migration-local model — does not depend on app/models, which later
  # tasks may delete.
  class MigrationFootage < ActiveRecord::Base
    self.table_name = "footages"
  end

  def up
    add_column :games, :footage_hours, :decimal, precision: 6, scale: 1, null: false, default: 0.0

    # Backfill: per game, sum a per-file footage rounded UP to the next 0.5 h.
    # Per file: 1800 s = 0.5 h. Integer-ceil the number of half-hours, then /2.0
    # to get decimal hours. Games with no footages stay at the default (0.0).
    MigrationFootage.group(:game_id).pluck(:game_id).each do |game_id|
      half_hours = MigrationFootage.where(game_id: game_id).sum do |footage|
        (footage.duration_seconds.to_i + 1799) / 1800
      end
      hours = half_hours / 2.0
      execute(<<~SQL.squish)
        UPDATE games SET footage_hours = #{hours} WHERE id = #{game_id.to_i}
      SQL
    end

    drop_table :footages
  end

  def down
    # NOTE: irreversible data loss — the per-file footage rows (filenames and
    # individual durations) are gone after `up` and cannot be restored. This
    # only recreates the empty table structure.
    create_table :footages do |t|
      t.datetime :created_at, null: false
      t.integer :duration_seconds
      t.string :filename, null: false
      t.bigint :game_id, null: false
      t.datetime :updated_at, null: false
      t.index [ :game_id, :filename ], name: "index_footages_on_game_id_and_filename", unique: true
    end
    add_foreign_key :footages, :games, on_delete: :cascade

    remove_column :games, :footage_hours
  end
end
