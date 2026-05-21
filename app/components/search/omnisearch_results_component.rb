# 2026-05-18 — Per-mode results wrapper for the omnisearch envelope.
#
# Replaces `app/views/shared/_omnisearch_results.html.erb`
# (dispatcher) + `app/views/games/_search_results_combined.html.erb`
# (:games_search shell) + `app/views/bundles/_search_results.html.erb`
# (:bundle_add shell). Single component, mode-aware, wraps the
# response body in the per-mode Turbo Frame and renders the section
# stack via `Search::OmnisearchSectionComponent` +
# `Search::OmnisearchResultRowComponent`.
#
# `:game_index` continues to delegate to the legacy
# `games/_search_results` partial (its row shape carries cover-image
# thumbnails + the IGDB-overwrite confirm modal trigger — out of
# scope for this refactor pass). The dispatcher branch lives here so
# the controller can call the component uniformly across all three
# modes.
#
# Args:
#   mode:    one of :game_index, :bundle_add, :games_search.
#   query:   sanitized query string (or blank when input is empty).
#   result:  Game::SearchService::Result struct for :bundle_add /
#             :games_search. For :game_index it is a Hash with
#             :results (IGDB rows) and :search_error (string or nil)
#             keys — passed through to the legacy partial.
#   bundle:  Bundle host for :bundle_add. Forwarded to per-row
#             [add] buttons.
module Search
  class OmnisearchResultsComponent < ViewComponent::Base
    # `:game_index` is intentionally absent here — that mode's
    # response shape (cover-image thumbnails + the IGDB-overwrite
    # confirm modal trigger) is still served by the legacy
    # `games/_search_results.html.erb` partial, which `GamesController#search`
    # renders directly. This component covers only the two omnisearch
    # surfaces that the partial chain previously fanned out into
    # `:bundle_add` and `:games_search`.
    MODES = %i[bundle_add games_search].freeze

    FRAME_IDS = {
      bundle_add:   "omnisearch_results_bundle_add",
      games_search: "omnisearch_results_games_search"
    }.freeze

    def initialize(mode:, query:, result:, bundle: nil)
      raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)
      @mode = mode
      @query = query.to_s
      @result = result
      @bundle = bundle
    end

    attr_reader :mode, :query, :result, :bundle

    def frame_id
      FRAME_IDS.fetch(mode)
    end

    def bundle_add?
      mode == :bundle_add
    end

    def games_search?
      mode == :games_search
    end

    # 2026-05-19 — Dropped `existing_games_by_igdb_id`. The dispatcher
    # (`Game::SearchService`) now strips any IGDB row whose id maps to
    # a local Game's `igdb_id` before the result reaches this view, so
    # the view never needs to flag "already-local" rows — they simply
    # don't appear in the IGDB section. Every IGDB row rendered here is
    # net-new, gets `[add]`, no `[open]` fallback exists.

    def has_local_games?
      result.respond_to?(:local_games) && result.local_games.any?
    end

    def has_local_bundles?
      result.respond_to?(:local_bundles) && result.local_bundles.any?
    end

    def has_igdb?
      result.respond_to?(:igdb) &&
        (result.igdb.any? || result.igdb_error.present?)
    end

    def igdb_error
      result.respond_to?(:igdb_error) ? result.igdb_error : nil
    end

    def truly_empty?
      result.local_games.empty? &&
        (!result.respond_to?(:local_bundles) || result.local_bundles.empty?) &&
        result.igdb.empty? &&
        igdb_error.blank?
    end
  end
end
