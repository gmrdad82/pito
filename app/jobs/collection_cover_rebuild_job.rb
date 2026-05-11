# Phase 27 §01h — Collection composite cover invalidator.
#
# Fires from `Game#after_update_commit` when `collection_id` changes
# (a game added to, moved between, or removed from a Collection).
# Sweeps the on-disk composite for BOTH the previous and the new
# collection id so the next page render re-derives them via
# `Collections::CoverComposer`. Either side may be nil (the game was
# orphaned / un-orphaned).
#
# > The job name says "rebuild" but the action is eviction only — no
# > actual rebuild is enqueued here. The composer runs synchronously
# > on first page render miss (cheap), so a separate rebuild job would
# > duplicate that path. The fingerprint check inside the composer
# > also catches the stale state as a fallback; eviction makes the
# > next render faster (no file → straight to rebuild without rehashing
# > the existing file).
#
# Argument shape:
#   perform(previous_collection_id, current_collection_id)
#
# Sidekiq runs in a separate process, so the in-memory `saved_changes`
# from the originating `after_update_commit` is gone by the time the
# job executes. The Game model passes both ids explicitly.
class CollectionCoverRebuildJob
  include Sidekiq::Job
  sidekiq_options queue: :default

  def perform(previous_collection_id, current_collection_id)
    [ previous_collection_id, current_collection_id ].compact.uniq.each do |cid|
      sweep_one(cid)
    end
  end

  private

  # Best-effort eviction. Survives `Errno::ENOENT` (file already gone)
  # and `Pito::AssetsRoot::Error` (defensive — a malformed id should
  # never reach this far, but we never want a stray callback to crash
  # a job retry chain).
  def sweep_one(collection_id)
    path = Pito::AssetsRoot.path("composites", "collection-#{collection_id}.jpg")
    File.delete(path) if File.exist?(path)
  rescue Errno::ENOENT, Pito::AssetsRoot::Error
    nil
  end
end
