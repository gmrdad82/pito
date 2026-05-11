# Phase 4 §6 — Collection controller. Default-create + rename on show page;
# destructive actions delegated to /deletions/:type/:ids (consistent with the
# rest of the project per CLAUDE.md "bulk-as-foundation").
class CollectionsController < ApplicationController
  include FriendlyRedirect

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  def index
    @collections = Collection.order(created_at: :desc)
  end

  def show
    @collection = Collection.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@collection) { |c| collection_path(c) }

    @games = @collection.games.order(:title)
  end

  def create
    collection = Collection.new
    collection.save!
    redirect_to collection_path(collection), notice: "collection created."
  end

  def update
    @collection = Collection.friendly.find(params[:id])
    if @collection.update(update_params)
      redirect_to collection_path(@collection), notice: "collection updated."
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    collection = Collection.friendly.find(params[:id])
    collection.destroy!
    redirect_to collections_path, notice: "collection deleted."
  end

  # Phase 27 follow-up (2026-05-11) — Collections modal pane.
  #
  # Returns the games belonging to `collection` as a Turbo Frame
  # fragment. The frame id matches the layout-level modal
  # (`collections_modal_frame`); the partial renders a grid of
  # `Games::CoverComponent` tiles linked to each game's show page.
  #
  # Auth and tenant scope match the rest of the surface (single-install,
  # multi-user — see CLAUDE.md). No format negotiation: the modal pane
  # is HTML-only.
  def games_pane
    @collection = Collection.friendly.find(params[:id])
    @games = @collection.games.order(Arel.sql("LOWER(games.title)"))
    render :games_pane, layout: false
  end

  private

  def update_params
    params.require(:collection).permit(:name)
  end
end
