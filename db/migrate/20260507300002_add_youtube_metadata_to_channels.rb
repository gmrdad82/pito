# Phase 7 — Step B (7b-youtube-client-and-audit.md) — additive
# YouTube metadata columns on the existing `channels` table. The
# placeholder columns from Phase 4 (`channel_url`, `star`,
# `connected`, `syncing`, `last_synced_at`) are UNTOUCHED — this is a
# pure additive migration. Phase 8 will populate these columns from
# `channels.list?mine=true`.
class AddYoutubeMetadataToChannels < ActiveRecord::Migration[8.1]
  def change
    change_table :channels, bulk: true do |t|
      t.string  :title
      t.text    :description
      t.bigint  :subscriber_count
      t.integer :video_count
      t.bigint  :view_count
      t.string  :thumbnail_url
      t.string  :etag
      t.datetime :synced_at
    end
  end
end
