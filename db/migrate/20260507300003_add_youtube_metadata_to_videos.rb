# Phase 7 — Step B (7b-youtube-client-and-audit.md) — additive
# YouTube metadata columns on the existing `videos` table.
#
# Implementation note (deviation from the spec body — see the rails-impl
# session log for rationale): the 7B spec described a "redesign" of
# `videos`, but the existing schema is NOT placeholder by Phase 7's
# arrival. Phase 4's bulk-operations / video_uploads / video_stats /
# timelines / playlist_items features all depend on the current shape
# (integer enum `privacy_status`, `made_for_kids`, `default_language`,
# etc.). A destructive redesign would break those features and their
# specs. The spec's locked decisions remain honored: the new YouTube
# metadata columns land here, the per-call audit lands in
# `youtube_api_calls`, and Phase 8's sync code can populate the new
# columns alongside the existing ones.
#
# Columns added:
#   - view_count (bigint)        — channels/videos/etc. statistics
#   - like_count (bigint)
#   - comment_count (bigint)
#   - etag (string)              — for conditional fetches
#   - synced_at (datetime)       — companion to last_synced_at; spec wires
#                                  the Pito-shape conversion to this name
#
# Existing columns retained:
#   - youtube_video_id (string, unique) — spec wanted not-null; existing
#                                          schema has nullable + unique
#                                          index. Keeping nullable to
#                                          avoid breaking Phase 4 data
#                                          ingest paths that allow null.
#   - title (string, nullable)         — spec wanted not-null; kept
#                                          nullable for the same reason.
#   - published_at (datetime, nullable)
#   - duration_seconds (integer, nullable)
#   - thumbnail_url (string, nullable)
#   - privacy_status (integer enum)    — spec wanted string enum; existing
#                                          integer enum is wired into
#                                          BulkOperation, VideoUpload, and
#                                          the Phase 4 trait specs.
class AddYoutubeMetadataToVideos < ActiveRecord::Migration[8.1]
  def change
    change_table :videos, bulk: true do |t|
      t.bigint   :view_count
      t.bigint   :like_count
      t.bigint   :comment_count
      t.string   :etag
      t.datetime :synced_at
    end

    # The spec asks for a `(tenant_id, channel_id, youtube_video_id)`
    # unique index. The existing global unique on `youtube_video_id`
    # already enforces a stronger constraint, but the composite index
    # is useful for the per-channel feed lookup pattern Phase 8 uses.
    add_index :videos,
              [ :tenant_id, :channel_id, :youtube_video_id ],
              unique: true,
              name: "index_videos_on_tenant_channel_youtube_id"

    # Companion index: per-channel feed ordered by published_at desc.
    add_index :videos,
              [ :tenant_id, :channel_id, :published_at ],
              order: { published_at: :desc },
              name: "index_videos_on_tenant_channel_published_at"
  end
end
