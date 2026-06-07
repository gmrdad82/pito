# frozen_string_literal: true

# Voyage embedding for a single Video. Mirrors `Game::VoyageIndexer`:
# build the multi-field text (`Video::EmbedText`), embed it via Voyage when a
# key is configured, persist the 1024-dim vector into `videos.summary_embedding`
# via `update_column` (skip callbacks).
#
# Diff-gate: a SHA256 digest of the embed text is stored in
# `videos.embedded_digest`; a re-run no-ops when the indexed fields are
# unchanged so routine YouTube re-imports (which bump `last_synced_at`/stats but
# not title/description/tags/category) do NOT burn a Voyage call. `force:`
# bypasses the gate.
#
# Empty input → no-op. Voyage not configured → no-op (silent). A nil vector
# raises so the job surfaces a visible failure + retry.
class Video
  class VoyageIndexer
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
      return unless AppSetting.voyage_configured?

      digest = Digest::SHA256.hexdigest(text)
      return if !@force && digest == @video.embedded_digest

      embed_and_persist(text, digest)
    end

    private

    def embed_and_persist(text, digest)
      vector = Voyage::Client.new.embed([ text ]).first
      if vector.nil?
        raise Pito::Error::VoyageEmbeddingNil.new(
          resource_type: "video", resource_id: @video.id
        )
      end

      @video.update_column(:summary_embedding, vector)
      @video.update_column(:embedded_digest, digest)
    end
  end
end
