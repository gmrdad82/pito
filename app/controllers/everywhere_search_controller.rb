# Phase 37 (2026-05-19) — "Everywhere" omnisearch endpoint.
#
# Standalone controller for the new global omnisearch surface
# (`/search/everywhere`). DISTINCT from the existing video-only
# `SearchController#show` per the user's strict-independence rule
# (2026-05-19): no shared base, no shared partials, no shared service.
#
# Flow:
#   1. The `/` flat-key on every page opens the layout-mounted
#      `<dialog id="omnisearch-modal-everywhere">` (rendered by
#      `Search::EverywhereModalComponent`).
#   2. As the user types, the `omnisearch-modal` Stimulus controller
#      GETs `/search/everywhere?q=<term>` into the dialog's nested
#      `<turbo-frame id="everywhere_results">`.
#   3. This action delegates to `Search::Everywhere` (the three-source
#      orchestrator: games + bundles + channels) and renders the
#      `Search::EverywhereResultsComponent` directly. The component
#      wraps the response body in its own turbo-frame so Turbo's
#      "matching frame" requirement is satisfied without a view file
#      adding a second wrapper.
#
# HTML format renders the component; JSON returns the raw orchestrator
# payload for the eventual CLI / MCP parity surface (locked in spec
# §"Required artifacts"). No layout — Turbo Frame swaps the body
# directly into the dialog.
class EverywhereSearchController < ApplicationController
  MAX_QUERY_LENGTH = 200

  def show
    query = params[:q].to_s.strip[0, MAX_QUERY_LENGTH].to_s
    current_path = params[:current_path].presence ||
                   params[:context].presence ||
                   request.path

    @result = Search::Everywhere.new(
      query: query,
      current_path: current_path,
      page: params[:page]
    ).call

    respond_to do |format|
      format.html do
        render(
          Search::EverywhereResultsComponent.new(
            query:        @result[:query],
            current_path: current_path,
            game_hits:    @result[:games][:hits] || [],
            bundle_hits:  @result[:bundles][:hits] || [],
            channel_hits: @result[:channels][:hits] || []
          ),
          layout: false
        )
      end
      format.json do
        render json: @result
      end
    end
  end
end
