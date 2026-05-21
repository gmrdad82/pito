# Phase 34 (2026-05-18) — Voyage embedding + Meilisearch indexing for
# a single Bundle.
#
# Mirrors `Game::VoyageIndexer` for Bundle records so the unified
# `/games` search corpus covers Bundles alongside Games. The flow:
#
#   1. Build the combined `"name — aggregated member summaries"` text.
#   2. Call `Voyage::Client#embed` for that text (when the API key
#      is configured). Persist the returned 1024-dim vector to
#      `bundles.summary_embedding` via `update_column` (skip
#      callbacks — no `after_save` rebuild loops).
#   3. Push the Bundle's document — including the freshly written
#      vector — into Meilisearch via `Meilisearch::BundleIndexer`.
#
# Gating: matches `Game::VoyageIndexer` — `AppSetting.voyage_configured?`
# gates the Voyage call. When the API key is blank the embedding step
# is skipped silently and we still push the BM25 document to
# Meilisearch so the keyword surface stays current.
#
# Empty inputs: when both `name` and every member summary are blank we
# no-op (no Voyage call, no Meilisearch push — there is nothing to
# search on). A bundle with a name but no members still indexes (the
# name alone is enough to find by typing).
#
# Idempotent on retry: re-running re-embeds and re-writes; the
# pgvector insert replaces the prior value, the Meilisearch upsert
# replaces the prior document.
class Bundle
  class VoyageIndexer
    MAX_MEMBER_SUMMARIES = 5

    def self.call(bundle)
      new(bundle).call
    end

    def initialize(bundle)
      @bundle = bundle
    end

    def call
      return if combined_text.blank?

      embedding = embed_and_persist if AppSetting.voyage_configured?
      Meilisearch::BundleIndexer.call(@bundle.reload, embedding: embedding)
    end

    private

    def embed_and_persist
      vector = Voyage::Client.new.embed([ combined_text ]).first
      return nil if vector.nil?

      # `update_column` skips validations + callbacks so this write
      # does not re-trigger `after_commit :enqueue_voyage_index` or
      # any other model side effect.
      @bundle.update_column(:summary_embedding, vector)
      vector
    end

    def combined_text
      parts = []
      parts << @bundle.name.to_s.strip if @bundle.name.present?
      summaries = aggregated_member_summaries
      parts << summaries if summaries.present?
      parts.join(" — ")
    end

    # Concatenate up to 5 member-game summaries with the em-dash
    # separator. Cap matches `Meilisearch::BundleIndexer` so the
    # embedded text matches the searchable text the index sees.
    def aggregated_member_summaries
      @bundle.games.first(MAX_MEMBER_SUMMARIES).map(&:summary).compact.reject(&:blank?).join(" — ")
    end
  end
end
