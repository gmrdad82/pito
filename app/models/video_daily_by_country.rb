# Phase 13.1 — Note 3 §V3. Sliced daily: (video_id, date,
# country_code). YouTube returns ISO 3166-1 alpha-2 codes plus `ZZ`
# for unknown.
class VideoDailyByCountry < ApplicationRecord
  belongs_to :video

  validates :date,         presence: true
  validates :country_code, presence: true
  validates :video_id,
            uniqueness: { scope: %i[date country_code],
                          message: "already has a row for this date and country" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_country, ->(code) { where(country_code: code) }
end
