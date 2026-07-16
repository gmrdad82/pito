# Background embedding indexer for a single Game.
#
# Thin wrapper around `Game::EmbeddingIndexer.call` — looks the row up,
# guards on a vanished record, hands off. Enqueued by:
#
#   - `Game::Igdb::SyncGame#call` success path (every IGDB sync re-embeds
#     the row, since `summary` may have just been overwritten).
#   - `NightlyReindexJob` (one job per Game).
#   - Console / future operator surfaces.
#
# Queue is `:search` — same lane as `VideoEmbedIndexJob` and
# `EventEmbedJob` (the other embed-indexing work). Keeps search
# throughput isolated from latency-sensitive sync jobs on `:default`.
#
# 2026-07-15 — Voyage decommission: renamed from the retired Voyage AI
# per-record job, repointed onto `Game::EmbeddingIndexer` (the local-embedder
# successor to the retired Voyage AI indexer).
class GameEmbedIndexJob < ApplicationJob
  queue_as :search

  # Transient nil embedding (sidecar hiccup / network blip) raises
  # EmbeddingNil. Retry with backoff rather than leaving the game
  # permanently unembedded. Mirrors VideoEmbedIndexJob + GameImportJob.
  retry_on Pito::Error::EmbeddingNil, wait: :polynomially_longer, attempts: 5

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Game::EmbeddingIndexer.call(game)
  end
end
