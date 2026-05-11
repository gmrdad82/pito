# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Open-diff registry. One open row per video at a time, enforced by a
# partial unique index on `(video_id) WHERE resolved_at IS NULL`. Per
# locked Q2: KEEP ALL resolved diffs (matches channel pattern). No
# expiry job ships in this phase.
#
# `payload` carries the diff as
#   { "field" => { "pito" => <pito_value>, "youtube" => <yt_value> } }.
# `resolution_payload` carries the user's decisions as
#   { "field" => "pito" | "youtube" }.
class CreateVideoDiffs < ActiveRecord::Migration[8.1]
  def change
    create_table :video_diffs do |t|
      t.bigint :video_id, null: false
      t.datetime :detected_at, null: false
      t.datetime :resolved_at
      t.jsonb :payload, null: false, default: {}
      t.jsonb :resolution_payload
      t.bigint :resolved_by_user_id

      t.timestamps
    end

    add_index :video_diffs, :video_id
    add_index :video_diffs, :resolved_at
    add_index :video_diffs, :resolved_by_user_id
    add_index :video_diffs, :video_id,
              unique: true,
              where: "resolved_at IS NULL",
              name: "index_video_diffs_open_per_video"

    add_foreign_key :video_diffs, :videos,
                    column: :video_id,
                    on_delete: :cascade
    add_foreign_key :video_diffs, :users,
                    column: :resolved_by_user_id,
                    on_delete: :nullify
  end
end
