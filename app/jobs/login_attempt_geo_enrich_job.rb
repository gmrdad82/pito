# Phase 25 — 01a (LD-4 fallback). Async backfill for `LoginAttempt`
# rows that missed geo on the synchronous path (DB missing, lookup
# over 5 ms, or transient enricher error).
#
# Idempotent: a row that already has `geo_country` set is a no-op so
# repeat enqueue / late-running jobs don't clobber a fresher value.
# A row that was deleted between enqueue and run is also a no-op.
class LoginAttemptGeoEnrichJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(attempt_id)
    attempt = LoginAttempt.find_by(id: attempt_id)
    return if attempt.nil?
    return if attempt.geo_country.present?

    Auth::GeoEnricher.reset_deferred!
    geo = Auth::GeoEnricher.call(attempt.ip)

    if geo[:city].blank? && geo[:region].blank? && geo[:country].blank?
      # Still empty — DB still missing or unknown IP. Don't churn the
      # row.
      return
    end

    attempt.update!(
      geo_city:    geo[:city],
      geo_region:  geo[:region],
      geo_country: geo[:country]
    )
  end
end
