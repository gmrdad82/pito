# Phase 35 (2026-05-19) — Background Voyage indexer for a single
# Channel.
#
# Thin wrapper around `Channels::VoyageIndexer.call` — looks the row
# up, guards on a vanished record, hands off. Enqueued by:
#
#   - `Channel` after_save_commit hook (every save re-embeds; the
#     indexer no-ops on blank input so this stays cheap for rows
#     before the first sync populates title / description /
#     keywords).
#   - `pito:voyage:reindex_channels` rake task (one job per
#     Channel).
#   - Console / future operator surfaces.
#
# Queue is `:search` — same lane as `GameVoyageIndexJob`,
# `BundleVoyageIndexJob`, `SearchIndexJob`, and `Notes::EmbedJob`.
# Keeps search throughput isolated from latency-sensitive sync jobs
# on `:default`.
class ChannelVoyageIndexJob < ApplicationJob
  queue_as :search

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    Channels::VoyageIndexer.call(channel)
  ensure
    # 2026-05-19 — push the post-index Stack-pane snapshot so any
    # open `/settings` tab sees the updated Voyage coverage +
    # Sidekiq counters without polling. Mirrors the existing
    # GameVoyageIndexJob / BundleVoyageIndexJob ensure blocks.
    #
    # Two-broadcast pattern (see `StackStatsBroadcastJob`):
    # - Immediate: captures the DB-state cells (Voyage embeddings,
    #   Meilisearch counts) that are already final by the time the
    #   indexer returned.
    # - Delayed 1s: captures the Sidekiq `busy` counter AFTER this
    #   worker thread releases its slot (the immediate broadcast
    #   still counts this worker as busy).
    StackStats::Broadcaster.broadcast!
    StackStatsBroadcastJob.set(wait: 1.second).perform_later
  end
end
