# Phase 22 §4.2 — RejectedVideoImport tombstone.
#
# Insert-only audit row. The keep/reject confirmation step writes one
# row per video the user chose NOT to keep, and the importer service
# diffs against this table on every subsequent import so previously-
# rejected YouTube video ids never re-appear.
#
# The unique (channel_id, youtube_video_id) DB index is the durable
# contract; the model-level uniqueness validator mirrors the index for
# faster fail-fast feedback in tests.
#
# Reversal (un-tombstoning) is out of scope for Phase 22; a future
# rake task will lift specific (channel, youtube_video_id) pairs.
class RejectedVideoImport < ApplicationRecord
  YOUTUBE_VIDEO_ID_REGEX = /\A[A-Za-z0-9_-]{11}\z/

  belongs_to :channel
  belongs_to :rejected_by, class_name: "User"

  validates :youtube_video_id,
            presence: true,
            format: { with: YOUTUBE_VIDEO_ID_REGEX },
            uniqueness: { scope: :channel_id, case_sensitive: true }
  validates :rejected_at, presence: true
end
