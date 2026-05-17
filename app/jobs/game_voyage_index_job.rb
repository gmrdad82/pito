# Phase 34 (2026-05-18) — Background Voyage + Meilisearch indexer for
# a single Game.
#
# Thin wrapper around `Games::VoyageIndexer.call` — looks the row up,
# guards on a vanished record, hands off. Enqueued by:
#
#   - `Igdb::SyncGame#call` success path (every IGDB sync re-embeds
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

    Games::VoyageIndexer.call(game)
  end
end
