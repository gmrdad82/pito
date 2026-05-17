# Omnisearch dispatcher — drives the shared `_omnisearch_modal`
# across the three modes documented in the modal partial:
#
#   :game_index   — IGDB only. Add-from-IGDB flow on `/games`.
#                   Result row action is `[add]` which POSTs `/games`
#                   with the IGDB id.
#   :bundle_add   — Local games (Meilisearch) + IGDB, with already-in-
#                   bundle games filtered out of the local half. Result
#                   row action is `[add]` which POSTs to
#                   `/bundles/:id/members` to associate the game.
#   :games_search — Local games + bundles + IGDB. Result rows navigate
#                   (game → `/games/:id`, bundle → opens the bundles
#                   modal on `/games` via deep-link).
#
# Returns a Hash keyed by record-type symbol so the per-mode results
# partial can read each pane independently. Unknown modes raise so the
# caller learns about typos at controller-test time rather than
# silently returning an empty envelope.
module Games
  class SearchService
    MODES = %i[game_index bundle_add games_search].freeze

    Result = Struct.new(:mode, :query, :local_games, :local_bundles, :igdb, :igdb_error, keyword_init: true)

    def self.call(query:, mode:, bundle: nil)
      raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)

      query = query.to_s.strip
      local_games = []
      local_bundles = []
      igdb = []
      igdb_error = nil

      case mode
      when :game_index
        igdb, igdb_error = call_igdb(query)
      when :bundle_add
        local = Meilisearch::SearchGames.call(query, exclude_bundle: bundle)
        local_games = local[:games]
        igdb, igdb_error = call_igdb(query)
      when :games_search
        local = Meilisearch::SearchGames.call(query, include_bundles: true)
        local_games = local[:games]
        local_bundles = local[:bundles]
        igdb, igdb_error = call_igdb(query)
      end

      Result.new(
        mode: mode,
        query: query,
        local_games: local_games,
        local_bundles: local_bundles,
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
        rows = Igdb::Client.new.search_games(query, limit: 10)
        [ rows, nil ]
      rescue Igdb::Client::Error => e
        [ [], { kind: "upstream_unavailable", message: e.message } ]
      end
    end
    private_class_method :call_igdb
  end
end
