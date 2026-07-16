# frozen_string_literal: true

# NL router's boot-time embedding cache. `config/pito/tools.yml`'s
# per-tool `nl_examples:` text is the source of truth; a row here is
# a materialized, embedded copy of one example phrase, keyed by
# `tool` (the owning chat tool) so the router can find its own
# neighbors fast without walking YAML on every request.
#
# `digest` (SHA256 of `phrase`) is the re-embed gate, mirroring the
# digest-gating already used on games/videos/conversations: rows
# materialize and embed lazily (at boot or first use), and a corpus
# edit in tools.yml only re-embeds the phrases that actually changed
# — an unchanged phrase keeps its cached vector. `embedding` is
# nullable on purpose: a row can exist digest-matched before the
# embeddinggemma sidecar (`Pito::Embedding::Client`, 768-dim) has
# gotten to it.
#
# Vectors are never shipped in the repo or seeded here — computing
# one requires the local sidecar, and a vector baked in by a
# different embeddinggemma engine version would silently skew cosine
# distances against freshly-computed ones.
#
# HNSW index mirrors db/migrate/20260715150000_add_embedding_to_events.rb:
# partial (`embedding IS NOT NULL`, since most rows start unembedded)
# and built `algorithm: :concurrently` (hence
# `disable_ddl_transaction!`) so a live instance never locks reads
# while the index builds during `pito update`.
class CreateNlExamples < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :nl_examples do |t|
      t.string :tool,    null: false
      t.text   :phrase,  null: false
      t.string :digest,  null: false
      t.vector :embedding, limit: 768

      t.timestamps
    end

    add_index :nl_examples, :digest, unique: true

    add_index :nl_examples, :embedding,
      using: :hnsw,
      opclass: :vector_cosine_ops,
      algorithm: :concurrently,
      where: "embedding IS NOT NULL",
      name: "index_nl_examples_on_embedding_hnsw"
  end
end
