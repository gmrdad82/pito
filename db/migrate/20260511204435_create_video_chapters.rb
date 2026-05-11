# Phase 11 §01a — Video edit page polish. Chapters live in their own
# table so the edit pane can stack add / remove rows without
# touching the description blob. Unique on `(video_id, start_seconds)`
# prevents two chapters claiming the same offset (YouTube semantics).
#
# Render order is `start_seconds ASC` (locked decision §4 in the
# parent plan). `position` is a stable ordering tiebreaker for forms
# that want it; render order is still seconds-driven.
class CreateVideoChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :video_chapters do |t|
      t.bigint :video_id, null: false
      t.integer :start_seconds, null: false
      t.string :label, null: false, limit: 100
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :video_chapters, :video_id
    add_index :video_chapters, [ :video_id, :start_seconds ], unique: true

    add_foreign_key :video_chapters, :videos,
                    column: :video_id,
                    on_delete: :cascade
  end
end
