# Phase 7 Path A2 (literal full retract). Strips Video down to a thin
# YouTube-reference record. After this migration the `videos` table
# holds:
#
#   id, tenant_id, youtube_video_id, channel_id, star,
#   oauth_identity_id (added in companion migration), last_synced_at
#   (added in companion migration), created_at, updated_at
#
# Every YouTube metadata column from Phase 4 placeholders and Phase 7B
# additive migrations is dropped. Video CRUD with arbitrary metadata is
# retired — Phase 8+ creates Videos via the connect-channel sync flow,
# never via an in-app form.
class DropYoutubeMetadataFromVideos < ActiveRecord::Migration[8.1]
  def change
    # The composite index on (tenant_id, channel_id, published_at)
    # references `published_at`, which we are about to drop. Remove the
    # index first.
    remove_index :videos,
                 column: [ :tenant_id, :channel_id, :published_at ],
                 name: "index_videos_on_tenant_channel_published_at",
                 if_exists: true

    change_table :videos, bulk: true do |t|
      t.remove :title,                type: :string
      t.remove :description,          type: :text
      t.remove :published_at,         type: :datetime
      t.remove :duration_seconds,     type: :integer
      t.remove :privacy_status,       type: :integer
      t.remove :made_for_kids,        type: :boolean, default: false, null: false
      t.remove :default_language,     type: :string
      t.remove :tags,                 type: :jsonb
      t.remove :scheduled_publish_at, type: :datetime
      t.remove :category_id,          type: :integer
      t.remove :like_count,           type: :bigint
      t.remove :comment_count,        type: :bigint
      t.remove :view_count,           type: :bigint
      t.remove :etag,                 type: :string
      t.remove :synced_at,            type: :datetime
      t.remove :thumbnail_url,        type: :string
    end
  end
end
