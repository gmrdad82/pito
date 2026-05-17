# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Bundles controller.
#
# After the 2026-05-17 simplification a Bundle has exactly one
# user-facing attribute: `name`. Both the create form and the edit
# form expose only `name`; everything else (composite cover, slug,
# members) is derived or managed through dedicated surfaces.
#
# Surface:
#   - index    : Flat grid of bundle composite covers.
#   - show     : Two-pane — cover/metadata + member list / add form.
#   - new      : Single `name` field.
#   - create   : Single `name` field.
#   - edit     : Single `name` field.
#   - update   : Permits `name`.
#   - destroy  : Routes through `/deletions/bundle/:ids` per the "no JS
#                confirms" rule.
#   - games_pane: Turbo Frame fragment listing the bundle's member
#                  games as `Games::CoverComponent` grid tiles — used
#                  by the `/games` bundles modal (replaces the former
#                  `Collections#games_pane`).
#
# The legacy `bundle_type` / `igdb_source_*` / `last_error` columns are
# gone; the `seed_from_igdb` action they served is removed.
class BundlesController < ApplicationController
  include FriendlyRedirect

  def index
    @bundles = Bundle.order(created_at: :desc)
  end

  def show
    @bundle = Bundle.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@bundle) { |b| bundle_path(b) }

    @members = @bundle.bundle_members.includes(:game).order(:position)
  end

  def new
    @bundle = Bundle.new
  end

  def create
    @bundle = Bundle.new(bundle_params)
    if @bundle.save
      redirect_to bundle_path(@bundle), notice: "bundle created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @bundle = Bundle.friendly.find(params[:id])
  end

  def update
    @bundle = Bundle.friendly.find(params[:id])
    if @bundle.update(bundle_params)
      redirect_to bundle_path(@bundle), notice: "bundle updated."
    else
      render :edit, status: :unprocessable_content
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
