# Phase 14 §1 — Games controller.
#
# Five action surfaces:
#   - `index`   — list view (Phase 14 §3 reskin pending)
#   - `show`    — full IGDB-backed detail page
#   - `search`  — `GET /games/search?q=…` (Turbo Frame from `_add_form`)
#   - `create`  — accepts either `params[:game][:igdb_id]` (new IGDB
#                  add-game flow) or no body (Phase 4 legacy "create
#                  empty Untitled game" — kept until polish window).
#   - `update`  — STRICTLY local-only fields. IGDB-sourced columns
#                  smuggled via params are silently dropped.
#   - `destroy` — Phase 4 carryover.
#   - `resync`  — `POST /games/:id/resync` enqueues `GameIgdbSync`.
class GamesController < ApplicationController
  MAX_QUERY_LENGTH = 100

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  def index
    @games = Game.order(created_at: :desc)
  end

  def show
    @game = Game.find(params[:id])
  end

  def search
    @query = params[:q].to_s.strip
    if @query.length > MAX_QUERY_LENGTH
      @query = @query[0, MAX_QUERY_LENGTH]
    end

    @results = []
    if @query.present?
      begin
        @results = Igdb::Client.new.search_games(@query, limit: 10)
      rescue Igdb::Client::Error => e
        @search_error = "igdb error: #{e.message}"
      end
    end

    render partial: "search_results",
           locals: { results: @results, query: @query, search_error: @search_error }
  end

  def create
    igdb_id_param = params.dig(:game, :igdb_id)

    # New IGDB add-game flow.
    if igdb_id_param.present?
      igdb_id = igdb_id_param.to_i
      if igdb_id <= 0
        redirect_to games_path, alert: "igdb id must be a positive integer." and return
      end

      existing = Game.find_by(igdb_id: igdb_id)
      if existing
        redirect_to game_path(existing),
                    alert: "already in your library."
        return
      end

      game = Game.new(igdb_id: igdb_id)
      if game.save
        GameIgdbSync.perform_async(game.id)
        redirect_to game_path(game), notice: "added; metadata loading in background."
      else
        redirect_to games_path, alert: "could not add game."
      end
      return
    end

    # Phase 4 legacy default-create — the "[+]" button on /games still
    # creates an empty "Untitled game" row. Deprecated copy in the flash
    # warns the user; the surface is removed in the polish window.
    game = Game.new
    game.save!
    redirect_to game_path(game),
                notice: "create empty game (legacy). use [search igdb] to add by id."
  end

  def update
    @game = Game.find(params[:id])
    if @game.update(local_only_params)
      redirect_to game_path(@game), notice: "game updated."
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    game = Game.find(params[:id])
    game.destroy!
    redirect_to games_path, notice: "game deleted."
  end

  def resync
    game = Game.find(params[:id])
    GameIgdbSync.perform_async(game.id)
    redirect_to game_path(game), notice: "refreshing from igdb…"
  end

  private

  # Phase 14 §1 — strict local-only allowlist. IGDB-sourced columns
  # smuggled into params are silently dropped (the `params.permit`
  # call only references local-only attributes).
  def local_only_params
    params.fetch(:game, {}).permit(
      :platform_owned_id,
      :played_at,
      :notes,
      :hours_of_footage_manual
    )
  end
end
