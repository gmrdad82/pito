# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Sidekiq job that builds
# a bundle's composite cover.
#
# Argument shape (sequential chain support added 2026-05-17):
#   perform(bundle_id)                — terminal (single rebuild, no chain).
#   perform(bundle_id, [next, third]) — rebuild bundle_id, then enqueue
#                                       the next job with [third].
#   perform(bundle_id, nil)           — equivalent to passing [].
#
# The chain pattern (orchestrated by `Bundle::CompositeRebuildQueue`)
# enqueues bundles in deterministic alphabetical order so multi-bundle
# fan-outs (e.g. a game's cover_image_id change rippling to N bundles)
# rebuild predictably.
#
# Looks up the bundle and delegates to `Bundle::Composite::Builder#call`. On
# bundle deleted mid-flight, no-ops gracefully AND still advances the
# chain — a deleted bundle is moot, not a failure.
#
# Failure semantics: when the composer raises, the chain BREAKS —
# remaining bundles are NOT processed. Sidekiq retries the failing head
# (`retry: 5`); the orchestrator's enqueue-next call is skipped because
# it sits AFTER the composer call.
#
# 2026-05-18 (live cover refresh) — after the composite is written the
# job broadcasts two Turbo Stream `replace` events on the per-bundle
# `"bundle_cover:<id>"` stream:
#
#   1. `target: "bundle_cover_<id>"` — the shelf-tile cover-wrap
#      rendered by `Game::BundleTileComponent` on /games (bundles
#      shelf) and /games/:id (bundles section, both halves). Partial:
#      `app/views/games/_bundle_tile_cover.html.erb`. The tile
#      component sizes the cover at either 150 × 200 (grid) or
#      98 × 130 (shelf); the broadcast uses the grid dimensions
#      (`width: 150, height: 200`) because the shelf-tile that lives
#      on /games is the dominant visible surface. Tiles rendered at
#      the smaller shelf size still get replaced — the wrapper id is
#      identical and the CSS sizes the inner img to the slot.
#   2. `target: "bundle_modal_composite_<id>"` — the bundles modal
#      composite wrapper rendered by
#      `app/views/bundles/_modal_composite.html.erb`. The partial
#      branches between the populated CSS-composite and the empty-
#      bundle netflix-3 placeholder, so the broadcast covers both the
#      "first add" (empty → populated) and "last remove" (populated →
#      empty) transitions.
#
# The broadcast is wrapped in a `rescue StandardError` so a Redis
# hiccup or Turbo wire failure never escapes the job's perform
# (mirroring the same `ensure`-block discipline `GameIgdbSync` and
# `ReindexAllJob` use). The cover file is the source of truth; a
# missed broadcast just means the next page render shows the new
# cover instead of a live update.
class BundleCoverBuild
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 5

  # Shelf-tile cover dimensions used when re-rendering
  # `_bundle_tile_cover` for the Turbo Stream broadcast. Matches the
  # `:grid` SIZES entry in `Game::BundleTileComponent` — the
  # dominant visible surface on /games. Tiles rendered at the
  # smaller `:shelf` size (98 × 130) share the same wrapper id, so
  # the broadcast still replaces them; the CSS sizes the inner
  # `<img>` to the slot.
  BROADCAST_TILE_WIDTH  = 150
  BROADCAST_TILE_HEIGHT = 200

  def perform(bundle_id, remaining_chain = nil)
    chain = Array(remaining_chain)
    rebuild_one(bundle_id)
    broadcast_cover_replace(bundle_id)
    enqueue_next(chain)
  end

  private

  # Look up + rebuild ONE bundle. A missing bundle (deleted between
  # enqueue and run) is a no-op WITHOUT a raise — the chain must not
  # strand on a moot id.
  def rebuild_one(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return if bundle.nil?

    Bundle::Composite::Builder.new.call(bundle)
  end

  # Broadcast Turbo Stream `replace` events for both consumer
  # surfaces (shelf tile cover-wrap + modal composite wrapper).
  # No-op when the bundle is gone (deleted mid-flight) — the open
  # consumer pages will already have been redirected / re-rendered
  # by the bundle's `before_destroy` cleanup. Swallows broadcast
  # errors so a transient Redis / Turbo wire failure does not retry
  # the entire build job.
  def broadcast_cover_replace(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return if bundle.nil?

    stream = "bundle_cover:#{bundle.id}"

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "bundle_cover_#{bundle.id}",
      partial: "games/bundle_tile_cover",
      locals: {
        bundle: bundle,
        width: BROADCAST_TILE_WIDTH,
        height: BROADCAST_TILE_HEIGHT,
        overflow_n: bundle.bundle_members.size - 9
      }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: "bundle_modal_composite_#{bundle.id}",
      partial: "bundles/modal_composite",
      locals: { bundle: bundle }
    )
  rescue StandardError
    nil
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
