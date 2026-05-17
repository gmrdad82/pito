# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Sidekiq job that builds
# a bundle's composite cover.
#
# Argument shape (sequential chain support added 2026-05-17):
#   perform(bundle_id)                — terminal (single rebuild, no chain).
#   perform(bundle_id, [next, third]) — rebuild bundle_id, then enqueue
#                                       the next job with [third].
#   perform(bundle_id, nil)           — equivalent to passing [].
#
# The chain pattern (orchestrated by `Bundles::CompositeRebuildQueue`)
# enqueues bundles in deterministic alphabetical order so multi-bundle
# fan-outs (e.g. a game's cover_image_id change rippling to N bundles)
# rebuild predictably.
#
# Looks up the bundle and delegates to `Composite::Builder#call`. On
# bundle deleted mid-flight, no-ops gracefully AND still advances the
# chain — a deleted bundle is moot, not a failure.
#
# Failure semantics: when the composer raises, the chain BREAKS —
# remaining bundles are NOT processed. Sidekiq retries the failing head
# (`retry: 5`); the orchestrator's enqueue-next call is skipped because
# it sits AFTER the composer call.
class BundleCoverBuild
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  def perform(bundle_id, remaining_chain = nil)
    chain = Array(remaining_chain)
    rebuild_one(bundle_id)
    enqueue_next(chain)
  end

  private

  # Look up + rebuild ONE bundle. A missing bundle (deleted between
  # enqueue and run) is a no-op WITHOUT a raise — the chain must not
  # strand on a moot id.
  def rebuild_one(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return if bundle.nil?

    Composite::Builder.new.call(bundle)
  end

  # Pop the next id off `chain` and enqueue a fresh run with the tail.
  # No-op when the chain is empty. Reached only after a successful
  # rebuild — a raise inside `rebuild_one` skips this method so Sidekiq
  # retries the head without re-firing the tail.
  def enqueue_next(chain)
    return if chain.empty?
    head, *tail = chain
    self.class.perform_async(head, tail)
  end
end
