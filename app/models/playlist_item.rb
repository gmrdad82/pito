class PlaylistItem < ApplicationRecord
  belongs_to :playlist
  belongs_to :video

  validates :youtube_playlist_item_id, presence: true, uniqueness: true
  validates :video_id, uniqueness: { scope: :playlist_id }
end
