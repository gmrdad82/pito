# Unit A0 (beta-2) — Channel read-only conversion.
#
# The channel is now a strictly one-way, read-only mirror
# (YouTube → pito); pito never writes channel attributes back to
# YouTube. The diff-reconciliation surface — the `ChannelDiff` model,
# its controller actions, routes, views, jobs, services, and the MCP
# diff tools — was removed in the same change. This migration drops
# the backing `channel_diffs` table.
#
# Reversible: the `up` direction drops the table; the `down` direction
# faithfully re-creates the original schema authored in
# `20260511024709_create_channel_diffs.rb` (same columns, same four
# indexes, same two foreign keys) so `db:rollback` works.
class DropChannelDiffs < ActiveRecord::Migration[8.1]
  def up
    drop_table :channel_diffs
  end

  def down
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
