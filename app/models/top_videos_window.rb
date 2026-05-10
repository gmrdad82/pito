# Phase 13.1 — Note 3 §C3 (leaderboard). One row per (channel_id,
# window, video_id). Up to 50 rows per (channel_id, window) per Note
# 3's `maxResults=50`. `rank` is densely materialized at sync time so
# dashboards do not re-sort on read.
class TopVideosWindow < ApplicationRecord
  belongs_to :channel
  belongs_to :video

  WINDOWS = %w[7d 28d 90d lifetime].freeze

  validates :window, presence: true, inclusion: { in: WINDOWS }
  validates :rank,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :channel_id,
            uniqueness: { scope: %i[window video_id],
                          message: "already appears on this leaderboard" }
  validate :rank_unique_within_channel_and_window

  scope :for_window, ->(window) { where(window: window) }
  scope :top_n,      ->(n) { order(:rank).limit(n) }

  private

  def rank_unique_within_channel_and_window
    return unless channel_id && window && rank

    scope = self.class.where(
      channel_id: channel_id,
      window: window,
      rank: rank
    )
    scope = scope.where.not(id: id) if persisted?
    return unless scope.exists?

    errors.add(:rank, "is already taken on this leaderboard")
  end
end
