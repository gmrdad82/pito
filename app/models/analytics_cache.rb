# frozen_string_literal: true

# Signature-keyed analytics cache row.
#
# Each row tracks one cacheable computation, identified by an opaque
# `signature` string. Status lifecycle:
#
#   pending → ready   (computation completed)
#   pending → failed  (computation raised)
#
# A row is "live" (usable) only when status == "ready" AND either
# expires_at is nil or expires_at is in the future.  Expired or failed
# rows are eligible to be reclaimed by Pito::Analytics::Cache.claim.
#
# Reads and writes go through Pito::Analytics::Cache — not this model directly.
class AnalyticsCache < ApplicationRecord
  self.table_name = "analytics_cache"

  STATUSES = %w[pending ready failed].freeze

  validates :signature, presence: true, uniqueness: true
  validates :status,    inclusion: { in: STATUSES }

  # True when this ready row's TTL has elapsed.  Always false for non-ready rows
  # (their expires_at semantics are undefined).
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # True when the row holds a usable cached result: ready and not expired.
  def live?
    status == "ready" && !expired?
  end
end
