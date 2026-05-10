# Phase 12 — playlist_items renamed to playlist_videos for terminology
# alignment with Note 1 (the YouTube Data API "playlistItems" resource).
# The schema, validations, and associations migrate over verbatim from
# the prior PlaylistItem model.
class PlaylistVideo < ApplicationRecord
  belongs_to :playlist
  belongs_to :video

  validates :youtube_playlist_item_id,
            presence: true,
            uniqueness: { case_sensitive: false }
  validates :video_id, uniqueness: { scope: :playlist_id }
  validates :position,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            }
end
