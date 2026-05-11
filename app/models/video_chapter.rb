# Phase 11 §01a — Video edit page polish. Chapters live in a
# dedicated table; render order is `start_seconds ASC`. Unique
# `(video_id, start_seconds)` is enforced at the DB layer.
#
# v1 does NOT write chapter timestamps into `videos.description` —
# the parent plan open question §5 reserves that follow-up for a
# later sync-back pass.
class VideoChapter < ApplicationRecord
  belongs_to :video

  validates :start_seconds,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :label, presence: true, length: { maximum: 100 }
  validates :start_seconds,
            uniqueness: {
              scope: :video_id,
              message: "must be unique per video"
            }

  scope :ordered, -> { order(:start_seconds) }
end
