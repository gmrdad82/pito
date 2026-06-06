# 2026-05-18 follow-up — Bulk Voyage embedder for `ReindexAllJob`.
#
# Replaces the per-record fan-out (`Game.find_each { ... perform_later }`)
# that turned a single `[reindex]` click into many game Voyage HTTP calls,
# all firing in a tight Sidekiq burst that tripped Voyage's per-minute rate
# limit and bombed the run with 429s.
#
# Voyage's `/v1/embeddings` accepts up to 128 input strings in a single
# request (see `Voyage::Client::MAX_BATCH_SIZE`). One bulk job per
# corpus collapses N HTTP calls into ceil(N/128) — for the current
# pito dataset (≪128 games), exactly ONE call.
#
# Scope: ONLY used by `ReindexAllJob`. The per-record job
# (`GameVoyageIndexJob`) stays live for the sync hooks — when a single
# game arrives from IGDB, batching one input is overkill and we want the
# existing forgiving per-row contract (`Voyage::Client#embed` returns
# nil on failure, no Sidekiq retry storm).
#
# R1 (2026-05-25) — bundle corpus removed; games only.
#
# Text-building MUST match the single-record indexers so a bulk
# reindex produces byte-identical Voyage inputs (and therefore
# byte-identical embeddings) to a per-row reindex:
#
#   - Game: "title — alt_names — summary" (em-dash, mirrors
#           `Game::VoyageIndexer#combined_text`; alt_names slot
#           omitted when alternative_names is empty)
#
# Error contract: `Voyage::Client#embed_batch` raises on non-2xx /
# missing key / malformed response. The job lets the raise propagate
# so Sidekiq records a visible failure + schedules a retry (rather
# than the per-row job's silent-nil pattern). The user can also see
# the upstream cause in the `[Voyage::Client]` log line.
class BulkVoyageIndexJob < ApplicationJob
  queue_as :search

  def perform(corpus:)
    case corpus.to_s
    when "games"
      embed_games
    else
      raise ArgumentError, "Unknown corpus: #{corpus.inspect} (expected 'games')"
    end
  end

  private

  # All games that have a usable summary. The query mirrors the per-row enqueue
  # filter (`Game.where.not(summary: nil)`) so the bulk job indexes
  # exactly the same set the old fan-out did.
  #
  # Reindex semantics:
  # - Records that DO NOT yet have a Voyage embedding → embed via Voyage.
  # - Records that ALREADY have a Voyage embedding → SKIP (no gratuitous
  #   Voyage API calls that could 429).
  def embed_games
    records = Game.where.not(summary: nil).where("summary <> ''").order(:id).to_a
    return if records.empty?

    needs_embed, _already_embedded = records.partition { |r| r.summary_embedding.nil? }
    embed_missing(needs_embed) if needs_embed.any?
  end

  # Voyage embed + write for records that have no vector yet. Slices
  # in MAX_BATCH_SIZE-sized groups; for pito's current corpus (≪128
  # of each) this loops once.
  def embed_missing(records)
    inputs = records.map { |r| game_text(r) }
    records.each_slice(Voyage::Client::MAX_BATCH_SIZE).zip(inputs.each_slice(Voyage::Client::MAX_BATCH_SIZE)).each do |batch_records, batch_inputs|
      embeddings = Voyage::Client.new.embed_batch(inputs: batch_inputs)
      batch_records.zip(embeddings).each do |record, embedding|
        next if embedding.nil? # embed_batch raises rather than nil-ing slots, but belt-and-braces
        record.update_column(:summary_embedding, embedding)
      end
    end
  end

  # Shared multi-field builder — single source of truth (see Game::EmbedText).
  def game_text(game)
    Game::EmbedText.call(game)
  end
end
