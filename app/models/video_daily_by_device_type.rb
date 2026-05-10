# Phase 13.1 — Note 3 §V4 (device split). Sliced daily: (video_id,
# date, device_type). YouTube vocab: MOBILE, TABLET, DESKTOP, TV,
# GAME_CONSOLE, UNKNOWN_PLATFORM.
class VideoDailyByDeviceType < ApplicationRecord
  belongs_to :video

  validates :date,        presence: true
  validates :device_type, presence: true
  validates :video_id,
            uniqueness: { scope: %i[date device_type],
                          message: "already has a row for this date and device" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_device_type, ->(device_type) { where(device_type: device_type) }
end
