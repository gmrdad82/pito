# frozen_string_literal: true

# Daily cache hygiene (0.9.0 Phase 2) — the ONE recurring touch the derived
# caches get. Lazy expiry handles correctness on read; this sweep just stops
# expired rows from accumulating (Phase-0 inventory found 399 of 435 primitive
# rows sitting expired, and api_requests grows unbounded).
#
#   1. `Pito::Analytics::Cache.sweep`      — expired analytics_cache rows.
#   2. expired `analytics_primitives` rows — expires_at elapsed (frozen rows
#      have expires_at NULL and are never touched).
#   3. `api_requests` audit rows older than RETENTION (90 days) — enough
#      history for the bench's request-volume baseline and quota forensics.
#
# `delete_all` everywhere: bulk cron path, no callbacks, no broadcasts.
class CacheSweepJob < ApplicationJob
  queue_as :default

  API_REQUESTS_RETENTION = 90.days

  def perform
    swept = {
      analytics_cache: Pito::Analytics::Cache.sweep,
      primitives:      AnalyticsPrimitive.where(expires_at: ..Time.current).delete_all,
      api_requests:    ApiRequest.where(created_at: ...API_REQUESTS_RETENTION.ago).delete_all
    }
    Rails.logger.info(
      "CacheSweepJob: #{swept.map { |table, count| "#{table}=#{count}" }.join(' ')}"
    )
    swept
  end
end
