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
#                  games as `Games::CoverComponent` grid tiles — used
#                  by the `/games` bundles modal (replaces the former
#                  `Collections#games_pane`).
class BundlesController < ApplicationController
  include FriendlyRedirect

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
        format.html { redirect_to bundle_path(@bundle), notice: "bundle updated." }
        format.json { render json: { id: @bundle.id, name: @bundle.name } }
      end
    else
      respond_to do |format|
        format.html { redirect_to bundle_path(@bundle), alert: @bundle.errors.full_messages.to_sentence }
        format.json { render json: { errors: @bundle.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  # `/bundles/:id` DELETE redirects to the action-confirmation screen
  # rather than destroying immediately, matching the project's
  # destructive-action posture (no JS confirms; everything goes
  # through the shared `_action_screen` partial).
  def destroy
    @bundle = Bundle.friendly.find(params[:id])
    redirect_to deletions_path(type: "bundle", ids: @bundle.id)
  end

  # Phase 27 follow-up (2026-05-17) — Bundles modal pane (formerly
  # `Collections#games_pane`). Returns the games belonging to `bundle`
  # as a Turbo Frame fragment. The frame id matches the layout-level
  # modal (`bundles_modal_frame`); the partial renders a grid of
  # `Games::CoverComponent` tiles linked to each game's show page.
  def games_pane
    @bundle = Bundle.friendly.find(params[:id])
    # The `bundle_members` association carries a default `order(:position)`
    # scope. `.reorder` drops it so the alphabetical title sort is the
    # sole ORDER BY clause (otherwise position wins and titles tie-break).
    @games = @bundle.games.reorder(Arel.sql("LOWER(games.title)"))
    render :games_pane, layout: false
  end

  private

  def bundle_params
    params.require(:bundle).permit(:name)
  end
end
