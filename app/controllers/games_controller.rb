# Phase 4 §3.3 / §6 — Game controller.
#
# Default-create + rename on show page. Cover-art upload via Active Storage
# `cover_art` attachment (variants `thumbnail`, `card`, `full` declared on
# the model). Variant generation requires libvips on the host (see Phase A
# log); attachment itself works without it.
class GamesController < ApplicationController
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  def index
    @games = Game.order(created_at: :desc)
  end

  def show
    @game = Game.find(params[:id])
  end

  def create
    game = Game.new(tenant: default_tenant)
    game.save!
    redirect_to game_path(game), notice: "game created."
  end

  def update
    @game = Game.find(params[:id])
    if @game.update(update_params)
      redirect_to game_path(@game), notice: "game updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    game = Game.find(params[:id])
    game.destroy!
    redirect_to games_path, notice: "game deleted."
  end

  private

  def update_params
    permitted = params.require(:game).permit(:title, :publisher, :cover_art, :collection_id)
    # platforms posted as a json string from the form (until a richer UI ships)
    if (raw_platforms = params.dig(:game, :platforms_json)).present?
      permitted[:platforms] = JSON.parse(raw_platforms)
    end
    permitted
  rescue JSON::ParserError
    permitted = params.require(:game).permit(:title, :publisher, :cover_art, :collection_id)
    permitted
  end

  def default_tenant
    Tenant.order(:id).first || Tenant.create!(name: "Primary")
  end
end
