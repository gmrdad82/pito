# Phase 13.1 — Note 3 §V5. Sliced daily: (video_id, date,
# traffic_source_type). YouTube vocab: YT_SEARCH, EXT_URL,
# RELATED_VIDEO, SUBSCRIBER, YT_CHANNEL, YT_OTHER_PAGE, PLAYLIST,
# NOTIFICATION, SHORTS, ... `video_thumbnail_impressions_click_rate`
# is YouTube-computed (non-summable).
class VideoDailyByTrafficSource < ApplicationRecord
  belongs_to :video

  validates :date,                presence: true
  validates :traffic_source_type, presence: true
  validates :video_id,
            uniqueness: { scope: %i[date traffic_source_type],
                          message: "already has a row for this date and traffic source" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_traffic_source, ->(type) { where(traffic_source_type: type) }
end
