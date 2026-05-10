# Phase 13.1 — Note 3 §C1. One row per (channel_id, date). The channel
# spine. Sync engine (Phase 13.2) populates daily; dashboard (Phase
# 13.3) consumes. Counters default 0; monetization columns default
# NULL until the sync engine flips MONETIZATION_ENABLED.
class ChannelDaily < ApplicationRecord
  belongs_to :channel

  validates :date, presence: true
  validates :channel_id,
            uniqueness: { scope: :date,
                          message: "already has a daily row for this date" }

  scope :for_window, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }
  scope :ordered_by_date, -> { order(:date) }
end
