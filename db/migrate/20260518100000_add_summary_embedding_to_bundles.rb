# Phase 34 (2026-05-18) — Voyage AI indexing for Bundle records in the
# unified `/games` search corpus.
#
# Mirrors `AddSummaryEmbeddingToGames` (2026-05-17): adds a 1024-dim
# pgvector column to `bundles` to hold an embedding of the bundle's
# `name + aggregated member-summary` string produced by
# `Bundles::VoyageIndexer`. Dimension matches Voyage AI's `voyage-3`
# model — the same model already used by `Games::VoyageIndexer` and
# `Notes::EmbedJob`. Changing the model later requires a fresh
# migration with the new dimension.
#
# Index is HNSW with `vector_cosine_ops` — cosine similarity is the
# canonical distance metric for Voyage's normalized embeddings. HNSW
# is pgvector's default ANN index; build is deferred per row (online
# build), so the migration is fast even on a populated table.
#
# The column is added proactively for parity with `games.summary_embedding`
# even though `Meilisearch::BundleIndexer` ALSO holds the embedding
# inline on the search document. Future near-neighbor queries that
# operate on Bundle vectors directly (e.g. "bundles similar to this
# bundle" / hybrid Postgres-side ranking) can index the column without
# a follow-up migration.
class AddSummaryEmbeddingToBundles < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :summary_embedding, :vector, limit: 1024
    add_index :bundles, :summary_embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_bundles_on_summary_embedding_hnsw"
  end
end
