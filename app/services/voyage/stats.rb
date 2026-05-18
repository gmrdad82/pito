# Phase 34 (2026-05-18) — Voyage AI stats snapshot.
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
# leaving the settings page. Wired into a view in a later dispatch
# (DR); this service is the data source only.
#
# Performance: pure SQL counts + a single max() — sub-millisecond on
# realistic catalog sizes. No caching needed. If this ever shows up
# in a profile, a 30 s `Rails.cache.fetch` wrap is the cheap fix.
#
# Bundle stats: `Bundle` does not currently carry a
# `summary_embedding` column (the DH dispatch adds it). When the
# column is absent, the bundle-related keys return nil so the view
# can render "—" without raising. When it lands, the same code path
# starts returning real numbers — no edit required here.
module Voyage
  class Stats
    def self.call
      new.call
    end

    def call
      games_embedded = Game.where.not(summary_embedding: nil).count
      games_total    = Game.count

      bundles_embedded, bundles_total = bundle_counts

      {
        configured: AppSetting.voyage_configured?,
        model: Voyage::Client::DEFAULT_MODEL,
        embedded_games_count: games_embedded,
        total_games_count: games_total,
        coverage_pct: coverage_pct(games_embedded, games_total),
        last_indexed_at: Game.where.not(summary_embedding: nil).maximum(:updated_at),
        embedded_bundles_count: bundles_embedded,
        total_bundles_count: bundles_total,
        storage_kb: compute_storage_kb,
        embeddings_last_24h: compute_recent_count
      }
    end

    private

    # 2026-05-18 (follow-up) — Sum `pg_total_relation_size` of the HNSW
    # vector indexes on `games.summary_embedding` (and `bundles.summary_embedding`
    # when that column is present). The HNSW index dominates the storage cost
    # of the embedding column itself, so this is a reasonable proxy for "how
    # much disk is the Voyage pipeline consuming on this install".
    #
    # Returns kilobytes (integer). Returns `nil` on any SQL error — the view
    # treats nil as "hide the cell" so a transient failure never blanks the
    # surrounding line.
    def compute_storage_kb
      index_names = [ "index_games_on_summary_embedding_hnsw" ]
      index_names << "index_bundles_on_summary_embedding_hnsw" if bundle_embedding_supported?

      quoted = index_names.map { |n| ActiveRecord::Base.connection.quote(n) }.join(",")
      result = ActiveRecord::Base.connection.execute(<<~SQL).first
        SELECT COALESCE(SUM(pg_total_relation_size(quote_ident(indexname)::regclass)), 0) AS total
        FROM pg_indexes
        WHERE indexname IN (#{quoted})
      SQL

      total_bytes = result && (result["total"] || result[:total]) || 0
      (total_bytes.to_i / 1024)
    rescue StandardError => e
      Rails.logger.warn "[Voyage::Stats] storage query failed: #{e.message}"
      nil
    end

    # Count of Game + Bundle rows that currently carry an embedding AND
    # were `updated_at` in the last 24 h. Proxy for "how active is the
    # embed pipeline right now" — surfaces a non-zero number when a
    # reindex / backfill ran recently. Returns 0 when nothing has happened
    # (the view hides the cell on 0).
    def compute_recent_count
      cutoff = 24.hours.ago
      games = Game.where.not(summary_embedding: nil).where("updated_at > ?", cutoff).count
      bundles =
        if bundle_embedding_supported?
          Bundle.where.not(summary_embedding: nil).where("updated_at > ?", cutoff).count
        else
          0
        end
      games + bundles
    rescue StandardError => e
      Rails.logger.warn "[Voyage::Stats] recent count query failed: #{e.message}"
      0
    end

    def coverage_pct(embedded, total)
      return 0.0 if total.to_i.zero?
      (embedded.to_f / total * 100).round(1)
    end

    def bundle_counts
      return [ nil, nil ] unless bundle_embedding_supported?
      [ Bundle.where.not(summary_embedding: nil).count, Bundle.count ]
    end

    def bundle_embedding_supported?
      Bundle.table_exists? && Bundle.column_names.include?("summary_embedding")
    rescue NameError, ActiveRecord::StatementInvalid
      false
    end
  end
end
