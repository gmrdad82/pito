# Phase 34 (2026-05-18) — Background Voyage + Meilisearch indexer for
# a single Bundle.
#
# Thin wrapper around `Bundles::VoyageIndexer.call` — looks the row up,
# guards on a vanished record, hands off. Enqueued by:
#
#   - `Bundle` after_commit hook on create / update (name or composite
#     metadata changed).
#   - `BundleMember` after_commit hook on create / destroy (membership
#     changed → aggregated summary changed).
#   - `pito:voyage:reindex_bundles` / `pito:voyage:reindex_all` rake
#     tasks (one job per Bundle).
#   - Console / future operator surfaces.
#
# Queue is `:search` — same lane as `GameVoyageIndexJob`,
# `SearchIndexJob`, and `Notes::EmbedJob`. Keeps search throughput
# isolated from latency-sensitive sync jobs on `:default`.
class BundleVoyageIndexJob < ApplicationJob
  queue_as :search

  def perform(bundle_id)
    bundle = Bundle.find_by(id: bundle_id)
    return unless bundle

    Bundles::VoyageIndexer.call(bundle)
  ensure
    # 2026-05-18 (DR follow-up) — push the post-index Stack-pane
    # snapshot so any open `/settings` tab sees the updated Voyage
    # coverage + Sidekiq counters without polling.
    StackStats::Broadcaster.broadcast!
  end
end
