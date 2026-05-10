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
  include FriendlyRedirect

  MAX_QUERY_LENGTH = 100

  # Phase 14 §1 polish (2026-05-10) — sortable columns on /games. Mirrors
  # the `ChannelsController` / `VideosController` shape: an `ALLOWED_SORTS`
  # whitelist maps user-facing keys to safe SQL column expressions, and
  # `sort_clause` builds an `Arel.sql` literal. Default sort stays
  # `created_at DESC` (matches the prior implicit ordering) so existing
  # bookmarks and the index spec keep their results.
  ALLOWED_SORTS = {
    "id" => "games.id",
    "title" => "games.title",
    "release_year" => "games.release_year",
    "igdb_rating" => "games.igdb_rating",
    "played_at" => "games.played_at",
    "igdb_synced_at" => "games.igdb_synced_at",
    "created_at" => "games.created_at"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  # Phase 14 §3 — Steam-shelf shelf width and "see all" filter cap.
  SHELF_LIMIT = 12
  GENRE_SHELF_CAP = 8

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Phase 14 §3 — Steam-shelf rewrite. The flat sortable table is gone.
  # The action exposes shelf-shaped collections plus a filtered
  # `all_games` page so `?genre=<id>` / `?platform_owned=<id>` "see
  # all" links land on a fully-listed surface.
  def index
    @bundles_shelf   = Bundle.order(updated_at: :desc).limit(10)
    @recently_played = Game.where.not(played_at: nil).order(played_at: :desc).limit(SHELF_LIMIT)

    @genres_shelves = Genre.joins(:games).distinct.order(:name).limit(GENRE_SHELF_CAP).map do |g|
      [ g, g.games.order(Arel.sql("igdb_rating DESC NULLS LAST")).limit(SHELF_LIMIT) ]
    end

    @platforms_shelves = Platform.joins(:games_owning).distinct.order(:name).map do |p|
      [ p, p.games_owning.order(Arel.sql("release_year DESC NULLS LAST")).limit(SHELF_LIMIT) ]
    end

    @filter = sanitized_filter
    scope = Game.all
    scope = scope.joins(:game_genres).where(game_genres: { genre_id: @filter[:genre_id] }) if @filter[:genre_id]
    scope = scope.where(platform_owned_id: @filter[:platform_owned_id])                    if @filter[:platform_owned_id]

    @all_games = scope.order(Arel.sql("release_year DESC NULLS LAST"))
  end

  def show
    @game = Game.friendly.find(params[:id])
    # rubocop:disable Style/RedundantReturn -- The `return` keyword guards
    # against a future DoubleRenderError if any code is added below the
    # canonical-slug redirect. Today the `show` action body ends here
    # (Rails implicit-renders `show.html.erb`), so rubocop sees the
    # `return` as redundant — but the guard mirrors the pattern used by
    # every other `friendly`-backed controller (channels, videos,
    # footages, bundles, collections, projects) and keeps the surface
    # safe to extend without re-deriving the rule.
    return if redirect_to_canonical_slug!(@game) { |g| game_path(g) }
    # rubocop:enable Style/RedundantReturn

    # show.html.erb reads @game directly; nothing else to set up here.
  end

  # Phase 14 §1 polish (2026-05-10) — show / edit split. The form
  # that used to live inline on show.html.erb moved to its own
  # `/games/:id/edit` screen so the show page reads as canonical
  # read-only metadata.
  def edit
    @game = Game.friendly.find(params[:id])
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
    @game = Game.friendly.find(params[:id])
    if @game.update(local_only_params)
      redirect_to game_path(@game), notice: "game updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    game = Game.friendly.find(params[:id])
    game.destroy!
    redirect_to games_path, notice: "game deleted."
  end

  # Phase 14 §1 polish (2026-05-10) — `[resync]` is async-and-locked.
  # If a previous resync is still in flight (`games.resyncing` true)
  # the action no-ops with a flash so the show page can keep its
  # animated indicator without an "already in flight" toast cascade
  # if the user re-clicks. Otherwise it enqueues `GameIgdbSync` —
  # the job itself rechecks the flag and self-locks via update_column.
  def resync
    game = Game.friendly.find(params[:id])
    if game.resyncing?
      redirect_to game_path(game), notice: "already resyncing." and return
    end
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

  def sanitized_sort_key
    ALLOWED_SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  def sanitized_dir
    requested = params[:dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : DEFAULT_DIR
  end

  def sort_clause
    column = ALLOWED_SORTS[params[:sort]] || ALLOWED_SORTS[DEFAULT_SORT]
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : DEFAULT_DIR
    Arel.sql("#{column} #{direction} NULLS LAST")
  end

  # Phase 14 §3 — `/games?genre=<id>` and `/games?platform_owned=<id>`
  # filter routes power the per-shelf "[see all]" link. Both inputs
  # are integer ids; missing / non-positive values are dropped so
  # arbitrary `?genre=evil` strings reduce to "no filter applied".
  def sanitized_filter
    filter = {}
    genre_id = params[:genre].to_i
    platform_id = params[:platform_owned].to_i
    filter[:genre_id] = genre_id if genre_id.positive?
    filter[:platform_owned_id] = platform_id if platform_id.positive?
    filter
  end
end
