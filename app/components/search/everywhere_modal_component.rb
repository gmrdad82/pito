# Phase 37 — "everywhere" omnisearch modal shell.
#
# Standalone sibling of `Search::OmnisearchModalComponent`. Built fresh
# per the user's 2026-05-19 strict-independence rule: the existing
# /games omnisearch (modes `:game_index, :bundle_add, :games_search`)
# stays untouched, this component spans games + bundles + channels
# with context-aware section ordering driven by `current_path`.
#
# No inheritance / no template sharing with `OmnisearchModalComponent`.
# The `omnisearch-modal` Stimulus controller is reused by class-name
# binding (data-controller="omnisearch-modal") because that binding
# is pure CSS-class-name reference, not a component-template
# coupling.
#
# Args:
#   dialog_id:    DOM id for the `<dialog>` element (unique per page).
#   url:          server endpoint the Stimulus controller GETs as the
#                  user types — receives `?q=<term>`.
#   current_path: request.path string. Drives section-order resolution
#                  inside `Search::EverywhereResultsComponent`; passed
#                  through to the results-frame URL as `?context=`
#                  so the server-rendered results body can re-derive
#                  the order on each XHR.
module Search
  class EverywhereModalComponent < ViewComponent::Base
    RESULTS_FRAME_ID = "everywhere_results".freeze

    def initialize(dialog_id:, url:, current_path:)
      @dialog_id = dialog_id
      @url = url
      @current_path = current_path.to_s
    end

    attr_reader :dialog_id, :url, :current_path

    def results_frame_id
      RESULTS_FRAME_ID
    end

    def placeholder
      I18n.t("search.everywhere.placeholder")
    end
  end
end
