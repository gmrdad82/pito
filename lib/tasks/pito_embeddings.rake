# frozen_string_literal: true

# Full local-embedder reindex sweep — games, then videos, then events — the
# 3.0.0 successor `EventEmbedJob` name-drops as "not yet built for events"
# (mirroring the pre-3.0.0 `pito:voyage:reindex_videos` / `reindex_games`).
# One task covering all three collections because they share one operational
# moment: standing the `embedder` sidecar up for the first time, swapping its
# model, or changing the vector dimension.
#
# Every row goes through `Game::EmbeddingIndexer` / `Video::EmbeddingIndexer`
# / `Pito::Embedding::EventIndexer`, each digest-gated on the same
# `embedded_digest` column: a row whose indexed text is unchanged since its
# last successful embed is a no-op (no HTTP call, no write). That means this
# sweep is RESUMABLE FOR FREE — kill it mid-run and re-run the task, and
# already-embedded rows just skip back past instantly; there is no checkpoint
# file to manage.
#
#   FORCE=1            re-embed every row regardless of the digest gate
#   THROTTLE=<secs>     sleep between rows (courtesy to the CPU-bound sidecar)
#
# A per-row Pito::Error::EmbeddingNil (raised by the games/videos
# strict `embed_batch` path on a sidecar failure) is caught, logged, and
# counted as failed — one bad row must not sink a 300-row sweep. The events
# path is forgiving by design (`Pito::Embedding::EventIndexer` never raises;
# a nil vector is a silent no-write), so a swallowed event failure surfaces
# here as "skipped" rather than "failed" — same as any other digest-gated
# no-op, and self-heals on the next sweep.
def pito_embeddings_sweep!(label, scope, indexer, force:, throttle:)
  total = scope.count
  processed = embedded = skipped = failed = 0

  scope.find_each do |record|
    processed += 1
    digest_before = record.embedded_digest

    begin
      indexer.call(record, force: force)
    rescue Pito::Error::EmbeddingNil => e
      failed += 1
      msg = "  #{label} ##{record.id} FAILED: #{e.message}"
      puts msg
      Rails.logger.warn(msg)
    else
      # `update_column` (used by every indexer) writes the in-memory
      # attribute too, so `record` already reflects a successful embed —
      # no reload needed. Unchanged digest means the digest gate skipped
      # the row (or, for events, a forgiving nil embed was swallowed).
      record.embedded_digest == digest_before ? skipped += 1 : embedded += 1
    end

    puts "#{label}: #{processed}/#{total}" if (processed % 50).zero?
    sleep(throttle) if throttle&.positive?
  end

  puts "#{label}: #{embedded} embedded, #{skipped} skipped, #{failed} failed (#{total} total)"
  { embedded: embedded, skipped: skipped, failed: failed }
end

namespace :pito do
  namespace :embeddings do
    desc "Reindex games, videos, and events against the local embedder (FORCE=1, THROTTLE=<secs>)"
    task reindex: :environment do
      if ENV["PITO_EMBEDDER_URL"].blank?
        abort "pito:embeddings:reindex requires PITO_EMBEDDER_URL — start the " \
          "`embedder` compose sidecar first (see docker-compose.yml)."
      end

      force = ENV["FORCE"] == "1"
      throttle = ENV["THROTTLE"].presence&.to_f

      totals = [
        pito_embeddings_sweep!("games", Game.all, Game::EmbeddingIndexer, force: force, throttle: throttle),
        pito_embeddings_sweep!("videos", Video.all, Video::EmbeddingIndexer, force: force, throttle: throttle),
        pito_embeddings_sweep!(
          "events",
          Event.where(kind: Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS),
          Pito::Embedding::EventIndexer,
          force: force,
          throttle: throttle
        )
      ]

      grand = totals.each_with_object(Hash.new(0)) { |t, acc| t.each { |k, v| acc[k] += v } }
      puts ""
      puts "Done. #{grand[:embedded]} embedded, #{grand[:skipped]} skipped, #{grand[:failed]} failed overall."
    end
  end
end
