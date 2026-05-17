# Phase 34 (2026-05-18) — Voyage embedding + Meilisearch indexing for
# a single Game.
#
# Two-stage write:
#   1. Call `Voyage::Client#embed` for the combined `"title — summary"`
#      string. Persist the returned 1024-dim vector into
#      `games.summary_embedding` via `update_column` (skip callbacks
#      so this doesn't re-fire bundle composite rebuilds or any
#      `after_save` chain).
#   2. Push the Game's document — including the freshly written
#      vector — into Meilisearch via `Meilisearch::GameIndexer`.
#
# Gating: matches the `Notes::EmbedJob` pattern — `voyage_configured?`
# gates the Voyage call. When the API key is blank the embedding
# step is skipped silently and we still push the BM25 document to
# Meilisearch so the keyword surface stays current. CLAUDE.md
# locked the per-target `voyage_index_*` flag pattern OUT (Phase 29
# settings refactor); a configured key is the only signal.
#
# Empty inputs: when both `title` and `summary` are blank we no-op
# (no Voyage call, no Meilisearch push — there is nothing to
# search on). A row with a title but no summary still indexes
# (title alone is enough to find by typing).
#
# Idempotent on retry: re-running re-embeds and re-writes; the
# pgvector insert replaces the prior value, the Meilisearch upsert
# replaces the prior document.
module Games
  class VoyageIndexer
    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      return if @game.title.to_s.strip.blank? && @game.summary.to_s.strip.blank?

      embed_and_persist if AppSetting.voyage_configured?
      Meilisearch::GameIndexer.call(@game.reload)
    end

    private

    def embed_and_persist
      vector = Voyage::Client.new.embed([ combined_text ]).first
      return if vector.nil?

      # `update_column` skips validations + callbacks so this write
      # does not re-trigger `after_save_commit
      # :rebuild_bundle_composites_on_resync` (which the IGDB sync
      # already invoked) or any other model side effect. The
      # pgvector column accepts the array directly.
      @game.update_column(:summary_embedding, vector)
    end

    # `title — summary` matches the natural reading order operators
    # see in the IGDB modal and on the game show page; the em-dash
    # separator is the same affordance the rest of the UI uses for
    # title/subtitle compositions. Voyage tokenizes both halves
    # together so search queries that mix the title and a summary
    # phrase still embed near the document.
    def combined_text
      parts = []
      parts << @game.title.to_s.strip   if @game.title.present?
      parts << @game.summary.to_s.strip if @game.summary.present?
      parts.join(" — ")
    end
  end
end
