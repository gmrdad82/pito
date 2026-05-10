# Phase 14 §2 — Sidekiq job that builds a bundle's composite cover.
#
# Single argument `bundle_id`. Looks up the bundle and delegates to
# `Composite::Builder#call`. On bundle deleted mid-build, no-ops
# gracefully. On `Composite::TileFetchError` (IGDB CDN flake), stamps
# `last_error` on the bundle and re-raises so Sidekiq retries with
# exponential backoff (5 attempts).
class BundleCoverBuild
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return if bundle.nil?

    Composite::Builder.new.call(bundle)
  rescue Composite::TileFetchError => e
    bundle&.update_columns(last_error: "tile fetch: #{e.message}",
                           updated_at: Time.current)
    raise
  rescue StandardError => e
    bundle&.update_columns(last_error: "build: #{e.message}",
                           updated_at: Time.current)
    raise
  end
end
