# Phase 11 §01a — Video edit page polish. End-screens live in their
# own table. Up to 4 non-`none` rows per video (YouTube cap, enforced
# at the model layer). A single `kind: none` row marks "no end-screen
# needed" — model-level validation collapses to that one row on save.
#
# `kind` is an integer-backed enum on the model
# (`related_video / related_channel / related_playlist / none`).
# `target_id` and `target_label` are free-text in v1 (parent open
# question §6 — surfaced for later YouTube-side validation).
class CreateVideoEndScreens < ActiveRecord::Migration[8.1]
  def change
    create_table :video_end_screens do |t|
      t.bigint :video_id, null: false
      t.integer :kind, null: false, default: 0
      t.string :target_id
      t.string :target_label, limit: 100
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :video_end_screens, :video_id
    add_index :video_end_screens, [ :video_id, :position ]

    add_foreign_key :video_end_screens, :videos,
                    column: :video_id,
                    on_delete: :cascade
  end
end
