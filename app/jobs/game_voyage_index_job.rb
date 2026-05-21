# Phase 34 (2026-05-18) — Background Voyage + Meilisearch indexer for
# a single Game.
#
# Thin wrapper around `Game::VoyageIndexer.call` — looks the row up,
# guards on a vanished record, hands off. Enqueued by:
#
#   - `Game::Igdb::SyncGame#call` success path (every IGDB sync re-embeds
#     the row, since `summary` may have just been overwritten).
#   - `pito:voyage:reindex_games` rake task (one job per Game).
#   - Console / future operator surfaces.
#
# Queue is `:search` — same lane as `SearchIndexJob` and
# `Notes::EmbedJob` (the existing search-indexing work). Keeps
# search throughput isolated from latency-sensitive sync jobs on
# `:default`.
class GameVoyageIndexJob < ApplicationJob
  queue_as :search

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Game::VoyageIndexer.call(game)
  ensure
    # 2026-05-18 (DR follow-up) — push the post-index Stack-pane
    # snapshot so any open `/settings` tab sees the updated Voyage
    # coverage + Sidekiq counters without polling.
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
