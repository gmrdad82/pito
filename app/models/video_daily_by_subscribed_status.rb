# Phase 13.1 — Note 3 §V6 (subscribed_status only —
# creator_content_type deferred per master agent decision #1). Sliced
# daily: (video_id, date, subscribed_status). YouTube vocab:
# SUBSCRIBED, UNSUBSCRIBED.
class VideoDailyBySubscribedStatus < ApplicationRecord
  belongs_to :video

  validates :date,              presence: true
  validates :subscribed_status, presence: true
  validates :video_id,
            uniqueness: { scope: %i[date subscribed_status],
                          message: "already has a row for this date and status" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_subscribed_status, ->(status) {
    where(subscribed_status: status)
  }
end
