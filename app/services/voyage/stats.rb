# Voyage AI stats snapshot.
#
# Cheap aggregate read returning a hash describing the current state
# of the Voyage embedding pipeline:
#
#   - whether credentials are configured (delegated to `AppSetting`)
#   - the locked embedding model (from `Voyage::Client`)
#   - per-target counts (embedded vs total) and coverage percentage
#   - last-indexed timestamp (max `updated_at` across embedded rows)
#
# Consumed by the `/settings` stack pane next to the [reindex] action
# so operators can see at a glance how the index is doing without
# leaving the settings page.
#
# R1 (2026-05-25) — bundle stats removed; games only.
#
# Performance: pure SQL counts + a single max() — sub-millisecond on
# realistic catalog sizes. No caching needed. If this ever shows up
# in a profile, a 30 s `Rails.cache.fetch` wrap is the cheap fix.
module Voyage
  class Stats
    def self.call
      new.call
    end

    def call
      games_embedded = Game.where.not(summary_embedding: nil).count
      games_total    = Game.count

      {
        configured: AppSetting.voyage_configured?,
        model: Voyage::Client::DEFAULT_MODEL,
        embedded_games_count: games_embedded,
        total_games_count: games_total,
        coverage_pct: coverage_pct(games_embedded, games_total),
        last_indexed_at: Game.where.not(summary_embedding: nil).maximum(:updated_at),
        storage_kb: compute_storage_kb,
        embeddings_last_24h: compute_recent_count
      }
    end

    private

    # Sum `pg_total_relation_size` of the HNSW vector index on
    # `games.summary_embedding`. The HNSW index dominates the storage cost
    # of the embedding column itself, so this is a reasonable proxy for "how
    # much disk is the Voyage pipeline consuming on this install".
    #
    # Returns kilobytes (integer). Returns `nil` on any SQL error — the view
    # treats nil as "hide the cell" so a transient failure never blanks the
    # surrounding line.
    KNOWN_HNSW_INDEXES = {
      games: "index_games_on_summary_embedding_hnsw"
    }.freeze
    private_constant :KNOWN_HNSW_INDEXES

    def compute_storage_kb
      index_names = [ KNOWN_HNSW_INDEXES[:games] ]

      sql = <<~SQL
        SELECT COALESCE(SUM(pg_total_relation_size(quote_ident(indexname)::regclass)), 0) AS total
        FROM pg_indexes
        WHERE indexname IN (?)
      SQL
      sanitized = ActiveRecord::Base.sanitize_sql_array([ sql, index_names ])
      result = ActiveRecord::Base.connection.execute(sanitized).first

      total_bytes = result && (result["total"] || result[:total]) || 0
      (total_bytes.to_i / 1024)
    rescue StandardError => e
      Rails.logger.warn "[Voyage::Stats] storage query failed: #{e.message}"
      nil
    end

    # Count of Game rows that currently carry an embedding AND were
    # `updated_at` in the last 24 h. Proxy for "how active is the embed
    # pipeline right now" — surfaces a non-zero number when a reindex /
    # backfill ran recently. Returns 0 when nothing has happened
    # (the view hides the cell on 0).
    def compute_recent_count
      cutoff = 24.hours.ago
      Game.where.not(summary_embedding: nil).where("updated_at > ?", cutoff).count
    rescue StandardError => e
      Rails.logger.warn "[Voyage::Stats] recent count query failed: #{e.message}"
      0
    end

    def coverage_pct(embedded, total)
      return 0 if total.to_i.zero?
      (embedded.to_f / total * 100).round
    end
  end
end
