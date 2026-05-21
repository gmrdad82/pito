# 2026-05-18 — Shared omnisearch modal shell component.
#
# Replaces `app/views/shared/_omnisearch_modal.html.erb` per the
# CLAUDE.md "HTML structure = ViewComponent" rule. The three current
# consumers (the `/games` `[+]` IGDB-add modal, the `/`-keyed
# `/games` omnisearch modal, and the per-bundle add-member modal in
# the bundle modal) all instantiate this component directly with
# constructor args; no more template branching by a `:mode` local.
#
# Mode resolution:
#   - `:game_index`   — IGDB-only add-from-IGDB flow.
#   - `:bundle_add`   — local games (Meilisearch) with a leading
#                        recommendations shelf seeded by
#                        `Bundle::Recommender`. Requires `bundle:`.
#   - `:games_search` — local games + bundles + IGDB.
#
# Args:
#   mode:              one of :game_index, :bundle_add, :games_search.
#   dialog_id:         DOM id for the `<dialog>` (unique on the page).
#   url:               omnisearch endpoint the Stimulus controller hits.
#   placeholder:       input placeholder string (caller resolves I18n).
#   results_frame_id:  DOM id of the inner `<turbo-frame>`.
#   bundle:            Bundle instance — required for :bundle_add only.
module Search
  class OmnisearchModalComponent < ViewComponent::Base
    MODES = %i[game_index bundle_add games_search].freeze

    def initialize(mode:, dialog_id:, url:, placeholder:, results_frame_id:, bundle: nil)
      raise ArgumentError, "unknown mode: #{mode.inspect}" unless MODES.include?(mode)
      raise ArgumentError, ":bundle_add requires bundle:" if mode == :bundle_add && bundle.nil?

      @mode = mode
      @dialog_id = dialog_id
      @url = url
      @placeholder = placeholder
      @results_frame_id = results_frame_id
      @bundle = bundle
    end

    attr_reader :mode, :dialog_id, :url, :placeholder, :results_frame_id, :bundle

    # Recommendations are surfaced only on :bundle_add when the
    # recommender returns at least one row. Empty bundles + bundles
    # with no embedded members both yield Game.none and skip the
    # shelf.
    def recommendations
      return [] unless mode == :bundle_add && bundle
      @recommendations ||= Bundle::Recommender.call(bundle, limit: 10).to_a
    end

    def render_recommendations?
      recommendations.any?
    end
  end
end
