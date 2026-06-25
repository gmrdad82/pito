# frozen_string_literal: true

# Entity-agnostic per-video raw-count row — keyed by video + report + resolved
# date range — that composes into any scope (game / channel / @all). It is NOT
# keyed by game/channel: a video's primitive cached while analyzing one entity is
# reused with no YouTube call for any later entity that shares that video.
#
# Reads/writes go through Pito::Analytics::Primitives, not this model directly.
#
# expires_at semantics:
#   nil          → frozen forever (a finalized/completed period — see Window#finalized?)
#   future Time  → live (recent days can still move)
#   past Time    → expired (eligible for refetch / sweep)
class AnalyticsPrimitive < ApplicationRecord
  # report groups whose metrics are fetched per video (videos:-filtered).
  REPORTS = %w[scalars daily country device subscribed_status demographics retention].freeze

  validates :video_youtube_id, :period_token, :start_date, :end_date, :fetched_at, presence: true
  validates :report, inclusion: { in: REPORTS }
  validates :video_youtube_id, uniqueness: { scope: %i[report start_date end_date] }

  # Rows whose TTL has elapsed (frozen rows — nil expires_at — are never expired).
  scope :expired, -> { where(expires_at: ..Time.current) }

  # Frozen rows never expire (finalized period).
  def frozen? = expires_at.nil?

  # A non-frozen row whose TTL has elapsed.
  def expired? = expires_at.present? && expires_at <= Time.current

  # Usable cached row: frozen, or not yet expired.
  def live? = !expired?
end
