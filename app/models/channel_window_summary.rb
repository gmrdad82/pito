# Phase 13.1 — Note 3 §C2. One row per (channel_id, window). The
# Studio-faithful ratios live here (averageViewPercentage, CTR rates,
# CPM) — never derived by SUM-ing across `channel_dailies`.
#
# `window` is a Postgres enum (`analytics_window`) holding one of `7d`,
# `28d`, `90d`, `lifetime`. Stored verbatim — no integer cast — so the
# Postgres-side enum and the AR-side strings round-trip directly.
class ChannelWindowSummary < ApplicationRecord
  belongs_to :channel

  WINDOWS = %w[7d 28d 90d lifetime].freeze

  validates :window, presence: true, inclusion: { in: WINDOWS }
  validates :window_start, presence: true
  validates :window_end,   presence: true
  validates :channel_id,
            uniqueness: { scope: :window,
                          message: "already has a summary for this window" }

  scope :for_window,      ->(window) { where(window: window) }
  scope :seven_d,         -> { where(window: "7d") }
  scope :twenty_eight_d,  -> { where(window: "28d") }
  scope :ninety_d,        -> { where(window: "90d") }
  scope :lifetime,        -> { where(window: "lifetime") }
end
