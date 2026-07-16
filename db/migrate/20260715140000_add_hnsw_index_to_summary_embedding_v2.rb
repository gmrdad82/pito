# frozen_string_literal: true

# Cosine HNSW indexes for the 768-dim embeddinggemma `summary_embedding_v2`
# columns added in 20260715133007. Mirrors the existing
# `index_{games,videos}_on_summary_embedding_hnsw` (vector_cosine_ops/hnsw)
# indexes on the retired 1024-dim Voyage `summary_embedding` columns.
#
# Built `algorithm: :concurrently` (hence `disable_ddl_transaction!`) so a
# live instance never locks reads while the index builds during `pito
# update` — `games`/`videos` keep serving similarity queries throughout.
class AddHnswIndexToSummaryEmbeddingV2 < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :games, :summary_embedding_v2,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      algorithm: :concurrently,
      name: "index_games_on_summary_embedding_v2_hnsw"

    add_index :videos, :summary_embedding_v2,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      algorithm: :concurrently,
      name: "index_videos_on_summary_embedding_v2_hnsw"
  end
end
