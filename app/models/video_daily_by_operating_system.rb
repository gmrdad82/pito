# Phase 13.1 — Note 3 §V4 (OS split). Sliced daily: (video_id, date,
# operating_system). YouTube vocab: IOS, ANDROID, WINDOWS, MACINTOSH,
# LINUX, OTHER, ...
class VideoDailyByOperatingSystem < ApplicationRecord
  belongs_to :video

  validates :date,             presence: true
  validates :operating_system, presence: true
  validates :video_id,
            uniqueness: { scope: %i[date operating_system],
                          message: "already has a row for this date and OS" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_operating_system, ->(os) { where(operating_system: os) }
end
