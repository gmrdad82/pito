# Background Voyage indexer for a single Game.
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

  # Transient Voyage nil (network blip / swallowed rate-limit) raises
  # VoyageEmbeddingNil. Retry with backoff rather than leaving the game
  # permanently unembedded. Mirrors VideoVoyageIndexJob + GameImportJob.
  retry_on Pito::Error::VoyageEmbeddingNil, wait: :polynomially_longer, attempts: 5

  def perform(game_id)
    game = Game.find_by(id: game_id)
    return unless game

    Game::VoyageIndexer.call(game)
  end
end
