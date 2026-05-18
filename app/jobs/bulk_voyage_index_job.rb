# 2026-05-18 follow-up — Bulk Voyage embedder for `ReindexAllJob`.
#
# Replaces the per-record fan-out (`Game.find_each { ... perform_later }`
# + `Bundle.find_each { ... perform_later }`) that turned a single
# `[reindex]` click into 13 game + 18 bundle Voyage HTTP calls, all
# firing in a tight Sidekiq burst that tripped Voyage's per-minute rate
# limit and bombed the run with 429s.
#
# Voyage's `/v1/embeddings` accepts up to 128 input strings in a single
# request (see `Voyage::Client::MAX_BATCH_SIZE`). One bulk job per
# corpus collapses N HTTP calls into ceil(N/128) — for the current
# pito dataset (≪128 of each), exactly ONE call per corpus.
#
# Scope: ONLY used by `ReindexAllJob`. The per-record jobs
# (`GameVoyageIndexJob`, `BundleVoyageIndexJob`) stay live for the
# sync hooks — when a single game arrives from IGDB or a bundle's
# membership changes, batching one input is overkill and we want the
# existing forgiving per-row contract (`Voyage::Client#embed` returns
# nil on failure, no Sidekiq retry storm).
#
# Text-building MUST match the single-record indexers so a bulk
# reindex produces byte-identical Voyage inputs (and therefore
# byte-identical embeddings) to a per-row reindex:
#
#   - Game:   "title — summary"  (em-dash, mirrors `Games::VoyageIndexer#combined_text`)
#   - Bundle: "name — agg(summaries)" (mirrors `Bundles::VoyageIndexer#combined_text`,
#             up to 5 member summaries em-dash joined)
#
# If the single-record builders ever change, update both call sites in
# lockstep or extract them to a shared text builder class. The current
# duplication is deliberate — keeping the bulk path independent means
# a bug in either does not poison the other.
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
    when "bundles"
      embed_bundles
    else
      raise ArgumentError, "Unknown corpus: #{corpus.inspect} (expected 'games' or 'bundles')"
    end
  ensure
    # 2026-05-18 (DR follow-up) — push the post-batch Stack-pane
    # snapshot to every open `/settings` tab. One broadcast per corpus
    # (NOT per record) — the prior per-row fan-out reasoning above
    # applies in reverse: 128 records → 1 broadcast, not 128.
    #
    # Two-broadcast pattern (see `StackStatsBroadcastJob`):
    # - Immediate: captures the DB-state cells (Voyage embeddings,
    #   Meilisearch counts) that are already final by the time the
    #   bulk indexer returned.
    # - Delayed 1s: captures the Sidekiq `busy` counter AFTER this
    #   worker thread releases its slot (the immediate broadcast
    #   still counts this worker as busy).
    StackStats::Broadcaster.broadcast!
    StackStatsBroadcastJob.set(wait: 1.second).perform_later
  end

  private

  # All games that have a usable summary (title alone is not embedded
  # in the per-row path either — see `Games::VoyageIndexer#call`'s
  # early-return when both title and summary are blank — but title-
  # only games are valid). The query mirrors the per-row enqueue
  # filter (`Game.where.not(summary: nil)`) so the bulk job indexes
  # exactly the same set the old fan-out did.
  #
  # Re-embed-everything semantics: this targets ALL games with a
  # summary, NOT only `summary_embedding: nil`. A `[reindex]` click
  # is the user's explicit "rebuild the search corpus" signal — we
  # want every row's vector refreshed, not just the unembedded ones.
  def embed_games
    records = Game.where.not(summary: nil).where("summary <> ''").order(:id).to_a
    return if records.empty?

    inputs = records.map { |g| game_text(g) }
    persist_in_batches(records, inputs) do |record, embedding|
      record.update_column(:summary_embedding, embedding)
      Meilisearch::GameIndexer.call(record.reload)
    end
  end

  # Bundles with at least one member-game that contributes summary
  # text. Mirrors `Bundles::VoyageIndexer#combined_text` — a bundle
  # with only `name` and no summarisable members still indexes (name
  # alone is enough to find by typing); a bundle with neither name nor
  # any summary text is skipped via `combined_text.blank?`.
  def embed_bundles
    records = Bundle.order(:id).to_a.reject { |b| bundle_text(b).blank? }
    return if records.empty?

    inputs = records.map { |b| bundle_text(b) }
    persist_in_batches(records, inputs) do |record, embedding|
      record.update_column(:summary_embedding, embedding)
      Meilisearch::BundleIndexer.call(record.reload, embedding: embedding)
    end
  end

  # Slice in MAX_BATCH_SIZE-sized groups and call Voyage once per
  # chunk. For pito's current corpus (≪128 of each) this loops once.
  # The chunking is future-proof for when the catalogue grows past
  # the per-request limit.
  def persist_in_batches(records, inputs)
    records.each_slice(Voyage::Client::MAX_BATCH_SIZE).zip(inputs.each_slice(Voyage::Client::MAX_BATCH_SIZE)).each do |batch_records, batch_inputs|
      embeddings = Voyage::Client.new.embed_batch(inputs: batch_inputs)
      batch_records.zip(embeddings).each do |record, embedding|
        next if embedding.nil? # embed_batch raises rather than nil-ing slots, but belt-and-braces
        yield(record, embedding)
      end
    end
  end

  # Mirrors `Games::VoyageIndexer#combined_text` — keep in sync.
  def game_text(game)
    parts = []
    parts << game.title.to_s.strip   if game.title.present?
    parts << game.summary.to_s.strip if game.summary.present?
    parts.join(" — ")
  end

  # Mirrors `Bundles::VoyageIndexer#combined_text` — keep in sync.
  def bundle_text(bundle)
    parts = []
    parts << bundle.name.to_s.strip if bundle.name.present?
    summaries = bundle.games.first(Bundles::VoyageIndexer::MAX_MEMBER_SUMMARIES)
                      .map(&:summary).compact.reject(&:blank?).join(" — ")
    parts << summaries if summaries.present?
    parts.join(" — ")
  end
end
