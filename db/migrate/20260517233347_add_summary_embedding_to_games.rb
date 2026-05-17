# Phase 34 (2026-05-18) — Voyage AI indexing for /games search.
#
# Adds a 1024-dim pgvector column to `games` for the combined
# `title — summary` embedding produced by `Games::VoyageIndexer`.
# Dimension matches Voyage AI's `voyage-3` model (the same model
# already used by `Notes::EmbedJob`); changing the model later
# requires a fresh migration with the new dimension.
#
# Index is HNSW with `vector_cosine_ops` — cosine similarity is the
# canonical distance metric for Voyage's normalized embeddings, and
# HNSW is the default ANN index for pgvector >= 0.5. Build is
# deferred per row (HNSW supports online build), so the migration
# itself is fast even on a populated table; the index becomes useful
# after `Games::VoyageIndexer` (or the `pito:voyage:reindex_games`
# rake task) populates rows.
class AddSummaryEmbeddingToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :summary_embedding, :vector, limit: 1024
    add_index :games, :summary_embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_games_on_summary_embedding_hnsw"
  end
end
