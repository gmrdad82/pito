# Phase 35 (2026-05-19) — Voyage AI indexing for Channel records.
#
# Mirrors `AddSummaryEmbeddingToBundles` (2026-05-18) and
# `AddSummaryEmbeddingToGames` (2026-05-17): adds a 1024-dim pgvector
# column to `channels` to hold an embedding of the channel's
# title / handle / description summary string produced by
# `Channels::VoyageIndexer`. Dimension matches Voyage AI's `voyage-3`
# model — the same model already used by `Games::VoyageIndexer`,
# `Bundles::VoyageIndexer`, and `Notes::EmbedJob`. Changing the model
# later requires a fresh migration with the new dimension.
#
# Index is HNSW with `vector_cosine_ops` — cosine similarity is the
# canonical distance metric for Voyage's normalized embeddings. HNSW
# is pgvector's default ANN index; build is deferred per row (online
# build), so the migration is fast even on a populated table.
#
# The column powers Postgres-side near-neighbor queries for channel
# recommendation surfaces (e.g. `Games::ChannelRecommendation` — games
# whose vector sits closest to a given channel's centroid). The column
# is added proactively so future channel-similarity surfaces can index
# it without a follow-up migration.
class AddSummaryEmbeddingToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :summary_embedding, :vector, limit: 1024
    add_index :channels, :summary_embedding,
              using: :hnsw,
              opclass: :vector_cosine_ops,
              name: "index_channels_on_summary_embedding_hnsw"
  end
end
