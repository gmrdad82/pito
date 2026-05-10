# Phase 13.1 — Note 3 §V8 (demographics). Sliced daily: (video_id,
# date, age_group, gender). YouTube vocab — age: AGE_13_17, AGE_18_24,
# AGE_25_34, AGE_35_44, AGE_45_54, AGE_55_64, AGE_65_PLUS. Gender:
# FEMALE, MALE, GENDER_OTHER. `viewer_percentage` is non-additive
# (Note 3 §V8 warning); the dashboard must not add extra dimensions.
class VideoDailyByAgeGroupGender < ApplicationRecord
  belongs_to :video

  validates :date,      presence: true
  validates :age_group, presence: true
  validates :gender,    presence: true
  validates :video_id,
            uniqueness: { scope: %i[date age_group gender],
                          message: "already has a row for this date, age, and gender" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :for_age_group, ->(group) { where(age_group: group) }
  scope :for_gender,    ->(gender) { where(gender: gender) }
end
