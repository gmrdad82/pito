# Local embedding for a single Game (3.0.0 local-embedding port).
#
# A faithful port of the retired Voyage AI indexer onto
# `Pito::Embedding::Client` — same public shape (`call(game, force:)`),
# same `combined_text` composition, same digest gating. Writes the
# `games.summary_embedding` (768-dim) column through the
# `Game::EMBEDDING_COLUMN` seam — the old 1024-dim Voyage AI column and its
# indexer were removed by the 2026-07-15 decommission sweep.
#
# Gating: `ENV["PITO_EMBEDDER_URL"]` blank means "not configured" (K2 —
# the feature degrades silently, no HTTP call).
#
# Empty inputs: when both `title` and `summary` are blank we no-op.
# A row with a title but no summary still indexes (title alone is
# enough to find by typing).
#
# Idempotent on retry: re-running re-embeds and re-writes; the
# pgvector insert replaces the prior value.
class Game
  class EmbeddingIndexer
    def self.call(game, force: false)
      new(game, force: force).call
    end

    def initialize(game, force: false)
      @game  = game
      @force = force
    end

    def call
      text = combined_text
      return if text.strip.blank?
      return if ENV["PITO_EMBEDDER_URL"].blank?

      digest = Digest::SHA256.hexdigest(text)
      # Diff-gate: skip re-embedding when the indexed fields are unchanged, so a
      # cover-art-only resync does NOT burn an embedder call. `force:` bypasses it.
      return if !@force && digest == @game.embedded_digest

      embed_and_persist(text, digest)
    end

    private

    def embed_and_persist(text, digest)
      # Strict client path — `#embed` swallows every failure into nil, so
      # the raised error would reach AppSignal cause-less. `#embed_batch`
      # raises `Pito::Embedding::Client::Error` naming the real failure;
      # converting it keeps the EmbeddingNil retry contract while the
      # incident message now carries the cause.
      begin
        vector = Pito::Embedding::Client.new.embed_batch(inputs: [ text ]).first
      rescue Pito::Embedding::Client::Error => e
        raise Pito::Error::EmbeddingNil.new(
          resource_type: "game", resource_id: @game.id, detail: e.message
        )
      end
      if vector.nil?
        raise Pito::Error::EmbeddingNil.new(
          resource_type: "game", resource_id: @game.id
        )
      end

      # `update_column` skips validations + callbacks so this write
      # does not re-trigger `after_save_commit
      # :rebuild_bundle_composites_on_resync` (which the IGDB sync
      # already invoked) or any other model side effect. The
      # pgvector column accepts the array directly.
      @game.update_column(Game::EMBEDDING_COLUMN, vector)
      @game.update_column(:embedded_digest, digest)
    end

    # `title — alt_names — summary` matches the natural reading order
    # operators see in the IGDB modal and on the game show page; the
    # em-dash separator is the same affordance the rest of the UI uses
    # for title/subtitle compositions. The embedder tokenizes all parts
    # together so search queries that mix the title and a summary
    # phrase still embed near the document.
    #
    # `alternative_names` joins the embedding input so the similar-games
    # + recommended-bundles clustering picks up alt-name signal (series
    # identifiers, localized names, marketing aliases). The alt names
    # are joined with single spaces inside their slot (they are short
    # tokens, not prose) before being em-dash-joined with the title +
    # summary slots.
    def combined_text
      Game::EmbedText.call(@game)
    end
  end
end
