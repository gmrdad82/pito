# frozen_string_literal: true

# Local-embedder indexing for a single Video (3.0.0 successor to the
# retired Voyage AI indexer — see `Pito::Embedding::Client` for the sidecar
# this replaces Voyage AI with). Mirrors `Game::EmbeddingIndexer`.
#
# Build the multi-field text (`Video::EmbedText`), embed it via the local
# embedder when `PITO_EMBEDDER_URL` is configured, persist the 768-dim
# vector into `videos.summary_embedding` (through the `Video::EMBEDDING_COLUMN`
# seam) via `update_column` (skip callbacks).
#
# Diff-gate: a SHA256 digest of the embed text is stored in
# `videos.embedded_digest` (shared with the legacy indexer); a re-run
# no-ops when the indexed fields are unchanged so routine YouTube
# re-imports (which bump `last_synced_at`/stats but not
# title/description/tags/category) do NOT burn an embedding call.
# `force:` bypasses the gate.
#
# Empty input → no-op. Embedder not configured → no-op (silent). A nil
# vector raises so the job surfaces a visible failure + retry.
class Video
  class EmbeddingIndexer
    def self.call(video, force: false)
      new(video, force: force).call
    end

    def initialize(video, force: false)
      @video = video
      @force = force
    end

    def call
      text = Video::EmbedText.call(@video)
      return if text.strip.blank?
      return if ENV["PITO_EMBEDDER_URL"].blank?

      # Salted with Pito::Embedding::Client::VECTOR_SPACE, not bare text
      # (3.0.1 correctness fix): the digest must identify the VECTOR SPACE a
      # stored embedding lives in, not just the source text. A text-only
      # digest can't detect a wire-level prompt change (e.g. the 3.0.0 ->
      # 3.0.1 PROMPT_PREFIX adoption) — the text is unchanged, so the digest
      # still matches, so the gate below would skip forever, leaving a
      # raw-space vector silently mismatched against prefixed queries. See
      # VECTOR_SPACE's doc comment for the full story.
      digest = Digest::SHA256.hexdigest(Pito::Embedding::Client::VECTOR_SPACE + text)
      # Diff-gate: skip only when the digest matches AND a vector is already
      # stored. The vector check matters: a matching digest with a NULL
      # vector is exactly what a 2.x -> 3.0.0 column promotion leaves behind
      # on every existing row (digest carries over, the new column starts
      # empty) — skipping on digest alone left those rows permanently
      # unembedded (3.0.1 P9-A). `force:` bypasses the whole gate.
      return if !@force && digest == @video.embedded_digest && @video.embedding_vector.present?

      embed_and_persist(text, digest)
    end

    private

    def embed_and_persist(text, digest)
      # Strict client path — mirrors Game::EmbeddingIndexer:
      # `embed_batch` raises with the real failure (sidecar down, malformed
      # response, missing slot), so the EmbeddingNil incident carries
      # its cause.
      begin
        vector = Pito::Embedding::Client.new.embed_batch(inputs: [ text ]).first
      rescue Pito::Embedding::Client::Error => e
        raise Pito::Error::EmbeddingNil.new(
          resource_type: "video", resource_id: @video.id, detail: e.message
        )
      end
      if vector.nil?
        raise Pito::Error::EmbeddingNil.new(
          resource_type: "video", resource_id: @video.id
        )
      end

      # One statement, like `Game::EmbeddingIndexer`: a mid-write crash can
      # never leave a fresh vector paired with a stale digest (or vice versa).
      @video.update_columns(Video::EMBEDDING_COLUMN => vector, embedded_digest: digest)
    end
  end
end
