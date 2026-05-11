# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Open-diff registry for channels. Mirrors the Phase 23 VideoDiff
# shape so the resolution surface (per-field decisions, partial unique
# index, append-only resolved-history) stays consistent across the
# two domain objects. One open row per channel at a time, enforced by
# a partial unique index on `(channel_id) WHERE resolved_at IS NULL`.
#
# `field_diffs` carries the diff as
#   { "field" => { "pito" => <pito_value>, "youtube" => <yt_value> } }.
# `resolution_payload` carries the user's decisions as
#   { "field" => { "decision" => "pito" | "youtube", "value" => <final> } }.
# Auto-closed diffs (cron pass finds no diff after a prior diff)
# stamp `{ "auto_closed" => true }`.
class CreateChannelDiffs < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_diffs do |t|
      t.bigint :channel_id, null: false
      t.datetime :detected_at, null: false
      t.datetime :resolved_at
      t.jsonb :field_diffs, null: false, default: {}
      t.jsonb :resolution_payload
      t.bigint :resolved_by_user_id

      t.timestamps
    end

    add_index :channel_diffs, :channel_id
    add_index :channel_diffs, :resolved_at
    add_index :channel_diffs, :resolved_by_user_id
    add_index :channel_diffs, :channel_id,
              unique: true,
              where: "resolved_at IS NULL",
              name: "index_channel_diffs_open_per_channel"

    add_foreign_key :channel_diffs, :channels,
                    column: :channel_id,
                    on_delete: :cascade
    add_foreign_key :channel_diffs, :users,
                    column: :resolved_by_user_id,
                    on_delete: :nullify
  end
end
