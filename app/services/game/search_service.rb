# Omnisearch dispatcher — drives the shared `_omnisearch_modal`
# across the two modes:
#
#   :game_index   — IGDB only. Add-from-IGDB flow on `/games`.
#                   Result row action is `[add]` which POSTs `/games`
#                   with the IGDB id.
#   :games_search — Local games + IGDB. Result rows navigate
#                   (game → `/games/:id`).
#
# R1 (2026-05-25) — `:bundle_add` mode removed with bundles.
#
# Returns a Hash keyed by record-type symbol so the per-mode results
# partial can read each pane independently. Unknown modes raise so the
# caller learns about typos at controller-test time rather than
# silently returning an empty envelope.
class Game
  class SearchService
    MODES = %i[game_index games_search].freeze

    Result = Struct.new(:mode, :query, :local_games, :igdb, :igdb_error, keyword_init: true)

    def self.call(query:, mode:)
      raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)

      query = query.to_s.strip
      local_games = []
      igdb = []
      igdb_error = nil

      case mode
      when :game_index
        # IGDB-only mode — no local corpus to gate against.
        igdb, igdb_error = call_igdb(query)
      when :games_search
        local = Pito::Search::Omnisearch.call(area: :games, query: query)
        local_games = local[:games]
        # 2026-05-19 — Reverse lazy IGDB. We always query both halves
        # so the user can compare the local row(s) against any IGDB
        # rows that match the same query. The Rule 1 dedup below
        # filters IGDB rows whose `id` is already the `igdb_id` of a
        # local hit, so duplicates don't double-render.
        igdb, igdb_error = call_igdb(query)
      end

      # Rule 1 — Dedup IGDB by local id. Filter out IGDB rows whose
      # `id` already exists as a local Game's `igdb_id`. The local row
      # wins. With the 2026-05-19 reverse-lazy switch the dedup now
      # carries every dispatch (not just :game_index) — local + IGDB
      # are both queried every time, so the dedup is what keeps the
      # IGDB pane from re-listing rows the user already imported.
      if igdb.any?
        local_igdb_ids = local_games.map(&:igdb_id).compact.to_set
        igdb = igdb.reject { |row| local_igdb_ids.include?(row["id"]) } if local_igdb_ids.any?
      end

      Result.new(
        mode: mode,
        query: query,
        local_games: local_games,
        igdb: igdb,
        igdb_error: igdb_error
      )
    end

    # IGDB call wrapped with the same upstream-error envelope the
    # existing `GamesController#search` uses — a network / auth /
    # rate-limit failure does not crash the surface; the partial
    # renders the `igdb_error` message in the IGDB section while
    # the local results (when present) stay usable.
    def self.call_igdb(query)
      return [ [], nil ] if query.blank?

      begin
        rows = Game::Igdb::Client.new.search_games(query, limit: 10)
        [ rows, nil ]
      rescue Game::Igdb::Client::Error => e
        [ [], { kind: "upstream_unavailable", message: e.message } ]
      end
    end
    private_class_method :call_igdb
  end
end
