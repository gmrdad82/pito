# Phase 14 §2 — Bundle cover invalidator.
#
# Fires from `Game#after_update_commit` when `cover_image_id` changes.
# Two responsibilities:
#   1. Evict the previous tile from `Bundle::Composite::TileCache` so the next
#      build re-downloads the new IGDB cover bytes (the cache key is
#      the cover_image_id; the old tile is now stale).
#   2. Enqueue a `BundleCoverBuild` sequential chain (via
#      `Bundle::CompositeRebuildQueue`) for every Bundle the Game
#      belongs to, so the composites rebuild in deterministic
#      alphabetical order rather than racing concurrent disk writes.
#
# Argument shape:
#   perform(game_id, previous_cover_image_id = nil)
#
# Sidekiq runs in a separate process, so the in-memory `saved_changes`
# from the originating `after_update_commit` is gone by the time the
# job executes. The Game model passes the old cover_image_id
# explicitly as the second positional arg.
#
# No-ops gracefully when the Game has been destroyed before the job
# runs.
class BundleCoverInvalidate
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform(game_id, previous_cover_image_id = nil)
    game = Game.find_by(id: game_id)
    return if game.nil?

    cache = Bundle::Composite::TileCache.new
    cache.evict(previous_cover_image_id) if previous_cover_image_id.present?

    Bundle::CompositeRebuildQueue.new.enqueue_for_game_resync(game)
  end
end
