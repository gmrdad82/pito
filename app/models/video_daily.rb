# Phase 13.1 — Note 3 §V1. One row per (video_id, date). The video
# spine. Same metric set as ChannelDaily; sync engine populates daily.
class VideoDaily < ApplicationRecord
  belongs_to :video

  validates :date, presence: true
  validates :video_id,
            uniqueness: { scope: :date,
                          message: "already has a daily row for this date" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :ordered_by_date, -> { order(:date) }
end
