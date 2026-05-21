# Phase 14 §2 / Phase 27 follow-up (2026-05-17 + 2026-05-18) — Bundles
# controller.
#
# After the 2026-05-18 follow-up, bundles are reachable only via the
# `/games` bundle shelf + modal flow. The standalone `/bundles` index
# and `/bundles/new` surfaces are gone, so the controller no longer
# carries `index`, `new`, `create`, or `edit`. A Bundle has exactly one
# user-facing attribute (`name`); the modal's inline-title-edit
# Stimulus controller PATCHes `update` with a JSON body to rename.
#
# Surface:
#   - show     : Two-pane — cover/metadata + member list / add form.
#                The bundles modal on `/games` deep-links here via the
#                tile's `[ open ]` anchor.
#   - update   : Permits `name`. Serves both an HTML branch (kept for
#                historical request specs and any direct hit) and a
#                JSON branch consumed by the modal's inline-title-edit.
#   - destroy  : Routes through `/deletions/bundle/:ids` per the "no JS
#                confirms" rule (reached from `/games/:id`'s
#                `[delete]`).
#   - games_pane: Turbo Frame fragment listing the bundle's member
#                  games as `Game::CoverComponent` grid tiles — used
#                  by the `/games` bundles modal (replaces the former
#                  `Collections#games_pane`).
class BundlesController < ApplicationController
  include FriendlyRedirect

  # 2026-05-18 — omnisearch query-length cap. Mirrors the value used by
  # `GamesController` (single-line guard against pathological inputs).
  MAX_QUERY_LENGTH = 100

  def show
    @bundle = Bundle.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@bundle) { |b| bundle_path(b) }

    @members = @bundle.bundle_members.includes(:game).order(:position)
  end

  # `update` is the modal's inline-title-edit endpoint. The Stimulus
  # `inline-title-edit` controller PATCHes `{ bundle: { name: ... } }`
  # as JSON and only needs a 200 / 422 verdict; the client updates the
  # modal title text optimistically on success. The HTML branch
  # survives so any direct PATCH (e.g. a future surface) still
  # round-trips through `redirect_to bundle_path(...)`.
  def update
    @bundle = Bundle.friendly.find(params[:id])
    if @bundle.update(bundle_params)
      respond_to do |format|
        format.html { redirect_to bundle_path(@bundle), notice: t("bundles.flash.updated") }
        format.json { render json: { id: @bundle.id, name: @bundle.name } }
      end
    else
      respond_to do |format|
        format.html { redirect_to bundle_path(@bundle), alert: @bundle.errors.full_messages.to_sentence }
        format.json { render json: { errors: @bundle.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  # 2026-05-18 — `[+]` create flow. The `/games` bundles-shelf heading
  # carries a bracketed `[+]` button that POSTs `/bundles` with NO body.
  # The action:
  #   1. Builds a Bundle with name `"unnamed bundle"` (or
  #      `"unnamed bundle N"` when collisions exist — see
  #      `next_unnamed_bundle_name`).
  #   2. Persists it. Composite cover is intentionally absent — the
  #      bundle has zero members on create, so `Composite::Builder`
  #      no-ops (see its early-return on empty `cover_image_ids`); the
  #      shelf tile + modal both fall back to the no-cover SVG (the
  #      grid-variant fallback the `BundleTileComponent` already
  #      renders when `composite_cover_url` is blank).
  #   3. Replies via Turbo Stream — appends the new tile to the shelf
  #      row (`bundles-shelf-row`), replaces the modal partial with
  #      pre-populated bundle locals + an auto-open Stimulus
  #      controller so the dialog opens immediately on the next render
  #      tick, and emits a flash notice via the shared toast region.
  #   4. The HTML fallback redirects to `/games` so a JS-off POST still
  #      yields the same created-bundle outcome (visible in the shelf
  #      on the next page load).
  def create
    @bundle = Bundle.create!(name: next_unnamed_bundle_name)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to games_path, notice: t("bundles.flash.created") }
    end
  end

  # 2026-05-18 — `/bundles/:id` DELETE now destroys directly. The
  # confirmation step is supplied by the per-bundle confirm modal
  # (`<dialog id="confirm_delete_bundle_<id>">`) rendered as a
  # sibling of each bundle tile in `_bundles_for_shelf`. That dialog
  # carries the project's no-JS-confirm posture: the form lives on
  # the page, the user clicks `[delete]` or presses `d` (via the
  # `bundle_delete_confirm` modal_actions keybindings) to submit;
  # there is no `window.confirm` / `data-turbo-confirm` anywhere in
  # the flow.
  #
  # Turbo Stream response (`destroy.turbo_stream.erb`):
  #   1. Removes the bundle's tile (`#bundle-tile-<id>`) from the
  #      shelf row.
  #   2. Replaces the bundles modal partial with the steady-state
  #      (no `bundle:` local) render so the next tile click starts
  #      from a clean modal — and the just-deleted bundle's state is
  #      gone from the DOM.
  #   3. Appends a flash notice to the toast container.
  #
  # HTML fallback (JS-off / direct hit): redirect to `/games` with
  # the same flash notice.
  def destroy
    @bundle = Bundle.friendly.find(params[:id])
    @bundle.destroy
    respond_to do |format|
      format.turbo_stream { flash.now[:notice] = t("bundles.flash.deleted") }
      format.html { redirect_to games_path, notice: t("bundles.flash.deleted") }
    end
  end

  # Phase 27 follow-up (2026-05-17) — Bundles modal pane (formerly
  # `Collections#games_pane`). Returns the games belonging to `bundle`
  # as a Turbo Frame fragment. The frame id matches the layout-level
  # modal (`bundles_modal_frame`); the partial renders a grid of
  # `Game::CoverComponent` tiles linked to each game's show page.
  def games_pane
    @bundle = Bundle.friendly.find(params[:id])
    # The `bundle_members` association carries a default `order(:position)`
    # scope. `.reorder` drops it so the alphabetical title sort is the
    # sole ORDER BY clause (otherwise position wins and titles tie-break).
    @games = @bundle.games.reorder(Arel.sql("LOWER(games.title)"))
    render :games_pane, layout: false
  end

  # 2026-05-18 — omnisearch endpoint for the bundle modal's "all games"
  # heading `[+]` trigger (`:bundle_add` mode). Runs the unified
  # `Game::SearchService` with the current bundle as the
  # `exclude_bundle:` so already-member games drop out of the local
  # half of the envelope. IGDB hits stay raw — adding from IGDB inside
  # the bundle modal is a two-step ("first sync IGDB into the library,
  # then add to the bundle"); the per-row action posts the local game
  # to `/bundles/:bundle_id/members`. Rendered through the shared
  # `_omnisearch_results` dispatcher.
  def search
    @bundle = Bundle.friendly.find(params[:id])
    @query  = params[:q].to_s.strip[0, MAX_QUERY_LENGTH]
    @result = Game::SearchService.call(query: @query, mode: :bundle_add, bundle: @bundle)
    render Search::OmnisearchResultsComponent.new(
      mode: :bundle_add, query: @query, result: @result, bundle: @bundle
    )
  end

  private

  def bundle_params
    params.require(:bundle).permit(:name)
  end

  # Returns the next available "unnamed bundle" name. If no bundle with
  # the base name exists, returns "unnamed bundle"; otherwise probes
  # "unnamed bundle 2", "unnamed bundle 3", ... and returns the first
  # un-taken slot. The lookup is case-sensitive against `bundles.name`
  # — matches the column's storage shape and the inline-title-edit
  # input's natural casing.
  #
  # The loop is bounded by the row count + 1: even when every previous
  # "unnamed bundle N" slot is taken, the next free index is at most
  # `Bundle.count + 1`. In practice the first miss returns immediately.
  def next_unnamed_bundle_name
    base = I18n.t("bundles.default_name")
    return base unless Bundle.exists?(name: base)

    n = 2
    loop do
      candidate = "#{base} #{n}"
      return candidate unless Bundle.exists?(name: candidate)
      n += 1
    end
  end
end
