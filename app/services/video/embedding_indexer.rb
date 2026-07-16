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

      digest = Digest::SHA256.hexdigest(text)
      return if !@force && digest == @video.embedded_digest

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

      @video.update_column(Video::EMBEDDING_COLUMN, vector)
      @video.update_column(:embedded_digest, digest)
    end
  end
end
