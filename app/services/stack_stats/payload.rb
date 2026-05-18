# 2026-05-18 (DR follow-up) — Single source of truth for the live
# `/settings` Stack-pane snapshot.
#
# Two callers:
#   1. `SettingsController#stack_stats` (kept as a JSON fallback /
#      diagnostics endpoint — see the controller comment for why).
#   2. `StackStats::Broadcaster.broadcast!` invoked from Sidekiq jobs
#      so any open `/settings` tab receives push updates over
#      ActionCable instead of polling every 3 seconds.
#
# The payload shape MUST stay byte-compatible with what the previous
# inline controller action returned — `stack_stats_live_controller.js`
# already knows the keys (`busy`, `scheduled`, `enqueued`,
# `voyage.embedded_games_count`, `postgres.games_rows`, …). When the
# JS controller asks "what is `postgres.games_rows`?", it does not
# care whether the source is HTTP-fetched or pushed via cable; the
# shape contract is the same.
#
# Shape contract (flat keys per section so the JS reads each cell with
# a single property access):
#
#   {
#     redis: { busy:, scheduled:, enqueued:, retry:, dead:,
#              processed:, failed: },
#     voyage: <Voyage::Stats.call merged with last_indexed_at_formatted>,
#     postgres: { games_rows:, games_size_bytes:,
#                 bundles_rows:, bundles_size_bytes: },
#     meilisearch: { games_docs:, games_size_bytes:, games_missing:,
#                    games_omit_size:, bundles_docs:, … },
#     assets: { cover_arts_files:, cover_arts_size_bytes:,
#               composites_files:, composites_size_bytes: }
#   }
#
# Errors swallow to `{}` per section so a transient Redis / Meilisearch
# blip never blanks the entire pane — the next broadcast (or the next
# refresh of a different section) retries.
module StackStats
  class Payload
    POSTGRES_TABLE_ROWS = [
      { label: "games", table: "games", class_name: "Game" },
      { label: "bundles", table: "bundles", class_name: "Bundle" }
    ].freeze

    ASSETS_CATEGORY_DIRECTORIES = {
      "cover arts" => [ "covers", "games" ],
      "composites" => [ "covers", "bundles" ]
    }.freeze

    SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

    def self.call
      new.call
    end

    def call
      {
        redis: redis_section,
        voyage: voyage_section,
        postgres: postgres_section,
        meilisearch: meilisearch_section,
        assets: assets_section
      }
    end

    private

    # ----- Voyage -----------------------------------------------------------

    def voyage_section
      voyage = Voyage::Stats.call
      voyage.merge(last_indexed_at_formatted: formatted_last_indexed_at(voyage[:last_indexed_at]))
    rescue StandardError
      {}
    end

    def formatted_last_indexed_at(ts)
      return nil if ts.nil?
      # Re-use the existing view helper so server-pushed cells render
      # the same string as the initial ERB render.
      ApplicationController.helpers.compact_time_ago(ts)
    rescue StandardError
      nil
    end

    # ----- Redis / Sidekiq --------------------------------------------------

    def redis_section
      require "sidekiq/api"
      stats = Sidekiq::Stats.new
      busy =
        begin
          Sidekiq::Workers.new.size
        rescue StandardError
          0
        end
      {
        busy: busy,
        scheduled: stats.scheduled_size,
        enqueued: stats.enqueued,
        retry: stats.retry_size,
        dead: stats.dead_size,
        processed: stats.processed,
        failed: stats.failed
      }
    rescue StandardError
      {}
    end

    # ----- Postgres per-table breakdown ------------------------------------

    def postgres_section
      rows = postgres_table_breakdown
      flat = {}
      rows.each do |row|
        key = row[:label].to_s
        flat["#{key}_rows".to_sym] = row[:count]
        flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
      end
      flat
    rescue StandardError
      {}
    end

    def postgres_table_breakdown
      conn = ActiveRecord::Base.connection
      POSTGRES_TABLE_ROWS.map do |row|
        if conn.table_exists?(row[:table])
          stats = postgres_table_stats(row[:table], row[:class_name])
          { label: row[:label], count: stats[:count], size_bytes: stats[:size_bytes] }
        else
          { label: row[:label], count: nil, size_bytes: nil }
        end
      end
    rescue StandardError
      []
    end

    def postgres_table_stats(table, class_name)
      Rails.cache.fetch([ "settings/pg-table-stats", "v2", table ], expires_in: 5.minutes) do
        compute_postgres_table_stats(table, class_name)
      end
    rescue StandardError
      compute_postgres_table_stats(table, class_name)
    end

    def compute_postgres_table_stats(table, class_name)
      conn = ActiveRecord::Base.connection
      quoted = conn.quote_table_name(table)
      size = conn.select_value(
        "SELECT pg_total_relation_size('#{quoted}')"
      )&.to_i
      count = class_name.safe_constantize&.count
      { count: count, size_bytes: size }
    rescue StandardError
      { count: nil, size_bytes: nil }
    end

    # ----- Meilisearch per-index breakdown ---------------------------------

    def meilisearch_section
      rows = search_per_index_stats
      flat = {}
      rows.each do |row|
        key = row[:label].to_s
        flat["#{key}_docs".to_sym] = row[:documents]
        flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
        flat["#{key}_missing".to_sym] = row[:missing] ? true : false
        flat["#{key}_omit_size".to_sym] = row[:omit_size] ? true : false
      end
      flat
    rescue StandardError
      {}
    end

    def search_per_index_stats
      engine_rows = {}

      if Search.engine.respond_to?(:per_index_stats)
        stats = Search.engine.per_index_stats
        stats.each do |index_name, payload|
          next if index_name.to_s.end_with?("_test")
          label = index_name.to_s.sub(/_(development|production)\z/, "")
          next unless SEARCH_INDEX_DISPLAY_ALLOWLIST.include?(label)
          engine_rows[label] = {
            documents: (payload[:documents] || payload["documents"] || 0).to_i,
            size_bytes: payload[:size_bytes] || payload["size_bytes"],
            raw_index_name: index_name.to_s
          }
        end
      end

      rows = []
      games_payload = engine_rows["games"]
      if games_payload
        games_docs, bundles_docs = split_games_index_by_kind(games_payload[:raw_index_name], games_payload[:documents])
        rows << {
          label: "games",
          documents: games_docs.to_i,
          size_bytes: games_payload[:size_bytes],
          missing: false
        }
        rows << {
          label: "bundles",
          documents: bundles_docs.to_i,
          size_bytes: nil,
          omit_size: true,
          missing: false
        }
      else
        rows << { label: "games", documents: 0, size_bytes: nil, missing: true }
        rows << { label: "bundles", documents: 0, size_bytes: nil, omit_size: true, missing: true }
      end
      rows
    rescue StandardError
      []
    end

    def split_games_index_by_kind(raw_index_name, total_documents)
      games_count = Search.engine.documents_count_for(raw_index_name, field: "kind", value: "game")
      bundles_count = Search.engine.documents_count_for(raw_index_name, field: "kind", value: "bundle")
      if games_count.nil? && bundles_count.nil?
        [ total_documents, 0 ]
      else
        [ games_count.to_i, bundles_count.to_i ]
      end
    rescue StandardError
      [ total_documents, 0 ]
    end

    # ----- Assets per-category breakdown -----------------------------------

    def assets_section
      rows = assets_breakdown
      flat = {}
      rows.each do |row|
        key = row[:label].to_s.tr(" ", "_")
        flat["#{key}_files".to_sym] = row[:file_count]
        flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
      end
      flat
    rescue StandardError
      {}
    end

    def assets_breakdown
      root = Pito::AssetsRoot.root
      return assets_breakdown_empty unless File.directory?(root)

      Rails.cache.fetch([ "settings/assets-breakdown", "v4", root.to_s ], expires_in: 5.minutes) do
        compute_assets_breakdown(root)
      end
    rescue StandardError
      assets_breakdown_empty
    end

    def compute_assets_breakdown(root)
      named = ASSETS_CATEGORY_DIRECTORIES.each_with_object({}) do |(label, _segments), acc|
        acc[label] = { label: label, file_count: 0, size_bytes: 0 }
      end

      ASSETS_CATEGORY_DIRECTORIES.each do |label, segments|
        child_path = File.join(root.to_s, *segments)
        next unless File.directory?(child_path)

        stats = compute_directory_volume_stats(child_path)
        named[label][:file_count] += stats[:file_count].to_i
        named[label][:size_bytes] += stats[:size_bytes].to_i
      end

      named.values
    rescue StandardError
      assets_breakdown_empty
    end

    def assets_breakdown_empty
      ASSETS_CATEGORY_DIRECTORIES.keys.map do |label|
        { label: label, file_count: 0, size_bytes: 0 }
      end
    end

    def compute_directory_volume_stats(path)
      size = 0
      count = 0
      Dir.glob(File.join(path.to_s, "**", "*"), File::FNM_DOTMATCH).each do |entry|
        next if File.basename(entry) == "." || File.basename(entry) == ".."
        next unless File.file?(entry)
        begin
          size += File.size(entry)
          count += 1
        rescue StandardError
          next
        end
      end
      { size_bytes: size, file_count: count }
    rescue StandardError
      { size_bytes: 0, file_count: 0 }
    end
  end
end
