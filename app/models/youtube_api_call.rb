# Phase 7 — Step B (7b-youtube-client-and-audit.md) — append-only
# audit row for every YouTube / OAuth-revocation API call. One row
# per logical call (final outcome) — `Youtube::Client`'s retry loop
# collapses retries into the single row that reflects the eventual
# success/failure (locked decision).
class YoutubeApiCall < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :google_identity, optional: true

  CLIENT_KINDS = %w[oauth public].freeze
  OUTCOMES = %w[
    success
    auth_failed
    quota_exceeded
    rate_limited
    server_error
    client_error
    network_error
  ].freeze

  validates :client_kind, presence: true, inclusion: { in: CLIENT_KINDS }
  validates :endpoint, presence: true
  validates :http_method, presence: true
  validates :units, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :outcome, presence: true, inclusion: { in: OUTCOMES }

  scope :today, ->(zone = "UTC") {
    where("created_at >= ?", Time.current.in_time_zone(zone).beginning_of_day)
  }

  # Append-only — `updated_at` was intentionally omitted from the
  # schema. Disable Rails' default `updated_at` writer.
  self.record_timestamps = false

  before_validation :stamp_created_at

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
