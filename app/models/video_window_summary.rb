# Phase 13.1 — Note 3 §V2. One row per (video_id, window). Mirrors
# `channel_window_summaries` for per-video Studio-faithful ratios.
class VideoWindowSummary < ApplicationRecord
  belongs_to :video

  WINDOWS = %w[7d 28d 90d lifetime].freeze

  validates :window, presence: true, inclusion: { in: WINDOWS }
  validates :window_start, presence: true
  validates :window_end,   presence: true
  validates :video_id,
            uniqueness: { scope: :window,
                          message: "already has a summary for this window" }

  scope :for_window,     ->(window) { where(window: window) }
  scope :seven_d,        -> { where(window: "7d") }
  scope :twenty_eight_d, -> { where(window: "28d") }
  scope :ninety_d,       -> { where(window: "90d") }
  scope :lifetime,       -> { where(window: "lifetime") }
end
