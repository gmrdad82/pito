class Playlist < ApplicationRecord
  belongs_to :channel

  # Phase 12 — playlist_items renamed to playlist_videos. Note 1
  # terminology: a "playlist video" is a single (playlist, video,
  # position) join row.
  has_many :playlist_videos, dependent: :destroy
  has_many :videos, through: :playlist_videos

  enum :privacy_status, { public_playlist: 0, unlisted: 1, private_playlist: 2 }

  validates :youtube_playlist_id, presence: true, uniqueness: { case_sensitive: false }
  validates :title, presence: true
end
