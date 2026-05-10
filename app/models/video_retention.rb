# Phase 13.1 — Note 3 §V7. Retention curve. One row per (video_id,
# elapsed_ratio_bucket). Recomputed-in-place each week; the table has
# `computed_at` (NOT `created_at` / `updated_at`).
class VideoRetention < ApplicationRecord
  belongs_to :video

  # Append-only / recomputed-in-place. The schema omits `updated_at`
  # entirely; only `computed_at` is stamped at write time.
  self.record_timestamps = false

  validates :elapsed_ratio_bucket,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 1
            }
  validates :video_id,
            uniqueness: { scope: :elapsed_ratio_bucket,
                          message: "already has a retention row for this bucket" }

  before_validation :stamp_computed_at

  scope :ordered_by_bucket, -> { order(:elapsed_ratio_bucket) }

  private

  def stamp_computed_at
    self.computed_at ||= Time.current
  end
end
