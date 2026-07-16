# frozen_string_literal: true

# Conversation search (3.0.0) — embed the scrollback itself. Allowlisted
# event kinds get their payload text embedded via the embeddinggemma
# sidecar (`Pito::Embedding::Client`, 768-dim), so the owner can search
# past conversations semantically. `embedded_digest` mirrors the
# digest-gating already used on games/videos: re-embed only when the
# embeddable text actually changed, never on every touch.
#
# Both columns are added NULL (instant on Postgres, no table rewrite).
# The HNSW index is partial (`embedding IS NOT NULL`) because most
# events never get embedded — echo/error chrome and other
# non-allowlisted kinds stay out of the graph entirely, keeping the
# index small and its recall focused on searchable content. Built
# `algorithm: :concurrently` (hence `disable_ddl_transaction!`) so a
# live instance never locks reads while the index builds during
# `pito update`.
class AddEmbeddingToEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :events, :embedding, :vector, limit: 768
    add_column :events, :embedded_digest, :string

    add_index :events, :embedding,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      algorithm: :concurrently,
      where: "embedding IS NOT NULL",
      name: "index_events_on_embedding_hnsw"
  end
end
