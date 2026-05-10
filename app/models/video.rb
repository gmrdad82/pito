class Video < ApplicationRecord
  include Searchable

  belongs_to :channel

  has_many :video_stats, dependent: :destroy
  has_many :playlist_items, dependent: :destroy
  has_many :playlists, through: :playlist_items

  # Phase 7 Path A2 (literal full retract). Video is now a thin
  # YouTube-reference record: youtube_video_id + channel + (optional)
  # oauth_identity tracking who synced it. All speculative metadata
  # (title, description, privacy_status, view_count, tags, etc.) is
  # gone; Phase 8+ rebuilds metadata caching from intentional
  # foundations. The Searchable concern stays included so reindex /
  # remove hooks fire — Video declares NO `searchable :*` /
  # `filterable :*` lines, which means the `searchable_fields` array
  # is empty and the search engine indexes only the id column. The
  # search surface remains functional for any other model that opts
  # into Searchable (currently none).
  belongs_to :oauth_identity,
             class_name: "GoogleIdentity",
             optional: true

  validates :youtube_video_id, presence: true, uniqueness: { case_sensitive: false }

  scope :starred, -> { where(star: true) }
end
