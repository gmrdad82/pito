# Phase 22 §4.2 — RejectedVideoImport tombstone.
#
# Insert-only tombstone. The keep/reject confirmation table writes one
# row per video the user chose NOT to keep; the daily import scan
# checks this table before recreating the corresponding Video. Reversal
# is a follow-up phase (rake task).
#
# Unique compound index `(channel_id, youtube_video_id)` is the
# contract: a channel can never accumulate two tombstones for the same
# YouTube video id. The index also short-circuits race conditions
# between two parallel keep/reject submissions.
class CreateRejectedVideoImports < ActiveRecord::Migration[8.1]
  def change
    create_table :rejected_video_imports do |t|
      t.references :channel, null: false, foreign_key: { on_delete: :cascade }
      t.string   :youtube_video_id,    null: false
      t.datetime :rejected_at,         null: false
      t.references :rejected_by, null: false,
                                 foreign_key: { to_table: :users, on_delete: :restrict }
      t.timestamps
    end

    add_index :rejected_video_imports,
              %i[channel_id youtube_video_id],
              unique: true,
              name: "index_rejected_video_imports_unique"
  end
end
