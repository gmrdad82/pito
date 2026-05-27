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
#      vector — into Meilisearch via `Game::MeilisearchIndexer`.
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
class Game
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
    end

    private

    def embed_and_persist
      vector = Voyage::Client.new.embed([ combined_text ]).first
      if vector.nil?
        # 2026-05-18 (DR) — surface the silent-failure case. The
        # Voyage HTTP client (`Voyage::Client#post_embeddings`)
        # rescues every `StandardError` and returns nil so a
        # transient network blip or a misconfigured key does not
        # crash the job; that hides the failure from operators
        # looking at the `/settings` Voyage stats row (which would
        # otherwise stay at `0/N games embedded` forever with no
        # log to explain why). Raise so Sidekiq records a visible
        # failure + schedules a retry. Operators can also see the
        # underlying cause in the `[Voyage::Client] embed failed`
        # log line emitted from the client.
        raise "Voyage embedding returned nil for game ##{@game.id} (api key configured but call failed — see prior log lines)"
      end

      # `update_column` skips validations + callbacks so this write
      # does not re-trigger `after_save_commit
      # :rebuild_bundle_composites_on_resync` (which the IGDB sync
      # already invoked) or any other model side effect. The
      # pgvector column accepts the array directly.
      @game.update_column(:summary_embedding, vector)
    end

    # `title — alt_names — summary` matches the natural reading order
    # operators see in the IGDB modal and on the game show page; the
    # em-dash separator is the same affordance the rest of the UI uses
    # for title/subtitle compositions. Voyage tokenizes all parts
    # together so search queries that mix the title and a summary
    # phrase still embed near the document.
    #
    # 2026-05-19 — `alternative_names` joins the embedding input so the
    # similar-games + recommended-bundles clustering picks up alt-name
    # signal (series identifiers, localized names, marketing aliases).
    # Mirrors the searchable-attributes addition in
    # `Game::MeilisearchIndexer::SEARCHABLE_ATTRIBUTES`. The alt names
    # are joined with single spaces inside their slot (they are short
    # tokens, not prose) before being em-dash-joined with the title +
    # summary slots.
    def combined_text
      parts = []
      parts << @game.title.to_s.strip if @game.title.present?
      if @game.respond_to?(:alternative_names) && @game.alternative_names.present?
        alt = Array(@game.alternative_names).map { |n| n.to_s.strip }.reject(&:blank?)
        parts << alt.join(" ") if alt.any?
      end
      parts << @game.summary.to_s.strip if @game.summary.present?
      parts.join(" — ")
    end
  end
end
