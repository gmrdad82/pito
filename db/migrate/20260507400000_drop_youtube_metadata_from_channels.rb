# Phase 7 Path A2 (literal full retract). Strips Channel down to a thin
# YouTube-reference record. Phase 4's speculative metadata caching is
# removed; Phase 8+ will rebuild from intentional foundations.
#
# Drops every YouTube-metadata column added in Phase 4 placeholders and
# Phase 7B additive migrations, plus the `connected` and `syncing`
# placeholder booleans. After this migration the `channels` table holds:
#
#   id, tenant_id, channel_url, star, oauth_identity_id, last_synced_at,
#   created_at, updated_at
#
# `connected` is replaced by `oauth_identity_id IS NOT NULL`. `syncing`
# is dropped without replacement — Phase 8's real sync wiring will own
# in-flight state when it ships.
class DropYoutubeMetadataFromChannels < ActiveRecord::Migration[8.1]
  def change
    # Drop the indexes that referenced soon-to-be-dropped columns first
    # so the column drops don't fail with "depended-on" errors.
    remove_index :channels,
                 column: [ :tenant_id, :connected ],
                 name: "index_channels_on_tenant_id_and_connected",
                 if_exists: true
    remove_index :channels,
                 column: [ :tenant_id, :syncing ],
                 name: "index_channels_on_tenant_id_and_syncing",
                 if_exists: true

    change_table :channels, bulk: true do |t|
      t.remove :connected,        type: :boolean, default: false, null: false
      t.remove :syncing,          type: :boolean, default: false, null: false
      t.remove :title,            type: :string
      t.remove :description,      type: :text
      t.remove :subscriber_count, type: :bigint
      t.remove :video_count,      type: :integer
      t.remove :view_count,       type: :bigint
      t.remove :thumbnail_url,    type: :string
      t.remove :etag,             type: :string
      t.remove :synced_at,        type: :datetime
    end
  end
end
