# Phase 14 §1 — Games controller.
#
# Five action surfaces:
#   - `index`   — list view (Phase 14 §3 reskin pending)
#   - `show`    — full IGDB-backed detail page
#   - `search`  — `GET /games/search?q=…` (Turbo Frame from `_add_form`)
#   - `create`  — IGDB add-game flow ONLY. Accepts `:igdb_id` (required)
#                  and an optional `:title` pre-seed from the IGDB
#                  search-result row. Phase 27 spec 04 (2026-05-17)
#                  REMOVED the legacy "default create empty game" branch
#                  — IGDB is the SINGLE entry point to creating a game
#                  in the library.
#   - `update`  — STRICTLY local-only fields. IGDB-sourced columns
#                  smuggled via params are silently dropped.
#   - `destroy` — Phase 4 carryover.
#   - `resync`  — `POST /games/:id/resync` enqueues `GameIgdbSync`.
class GamesController < ApplicationController
  include FriendlyRedirect
  include Games::FiltersHelper

  MAX_QUERY_LENGTH = 100

  # Phase 28 §01a — typeahead source cap (architect lean #2 locked).
  VERSION_PARENT_SEARCH_LIMIT = 20

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

  # Phase 14 §3 — Steam-shelf shelf width.
  # Phase 27 polish (2026-05-11) — `GENRE_SHELF_CAP` retired with the
  # legacy `@genres_shelves` iteration; the 01c-v2 nested Genres shelf
  # is the single source of truth for genre-grouped tile rows.
  SHELF_LIMIT = 12

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Phase 14 §3 — Steam-shelf rewrite. The flat sortable table is gone.
  # The action exposes shelf-shaped collections plus a filtered
  # `all_games` page so `?genre=<id>` / `?platform_owned=<id>` "see
  # all" links land on a fully-listed surface.
  #
  # Phase 27 §01c-v2 — Two top-of-page horizontal NESTED shelves
  # precede the existing shelves. The outer Genres shelf iterates one
  # sub-shelf per genre that owns at least one game; the outer Custom
  # collections shelf does the same for collections. Each sub-shelf is
  # a horizontally-scrolling row of game tiles at the `:shelf` cover
  # variant (collections additionally lead with a composite cover
  # tile). Empty buckets are HIDDEN — when no genre / collection owns
  # games, the corresponding outer section does not render at all.
  # Tiles below the `[see all]` link continue to point at
  # `/games?genre=<slug>` / `/games?collection=<slug>` which the
  # existing filter codepath narrows.
  def index
    @bundles_shelf   = Bundle.order(updated_at: :desc).limit(10)
    @recently_played = Game.where.not(played_at: nil).order(played_at: :desc).limit(SHELF_LIMIT)

    # Phase 27 §01c-v2 — outer nested shelves. The previous flat-tile
    # design (one tile per genre / collection, always rendered with a
    # muted "(none yet)" placeholder when empty) is replaced by an
    # outer shelf that iterates sub-shelves of game-cover tiles. Empty
    # genres / collections are HIDDEN end-to-end — the partial only
    # renders the outer `<section>` when at least one bucket has games
    # (01c-v2 locked decision #7 reverses the v1 placeholder rule).
    #
    # Scope rationale:
    #   - Genres outer-shelf — primary-genre scoping (2026-05-11
    #     follow-up). `Game.where.not(primary_genre_id: nil)` lists
    #     only genres that own at least one game pinned to them via
    #     `Games::PrimaryGenrePicker`. Result: every multi-genre game
    #     appears in EXACTLY ONE sub-shelf instead of every
    #     `game_genres` join it touches.
    #   - Collections outer-shelf — `Collection.joins(:games).distinct`
    #     remains the source (each game has a single `collection_id`
    #     pointer, no dedup concern).
    #   - Alphabetical case-insensitive ordering with a stable `id`
    #     tiebreak so render order is deterministic across requests.
    # Postgres requires DISTINCT + ORDER BY columns to appear in the
    # SELECT list. Subquery (`where(id: …)`) keeps the outer query
    # clean for ordering.
    @genres_for_shelf = Genre.where(
      id: Game.where.not(primary_genre_id: nil).distinct.select(:primary_genre_id)
    ).order(Arel.sql("LOWER(genres.name)"), :id)
    @collections_for_shelf = Collection.where(id: Collection.joins(:games).distinct.select(:id))
                                       .order(Arel.sql("LOWER(collections.name)"), :id)

    # Phase 27 P27 reviewer follow-up (non-blocking concern #2,
    # 2026-05-11) — single-pass batch for the per-genre sub-shelves.
    # Previously each `_genre_sub_shelf` render fired `base.count` +
    # `base.order(...).limit(30).to_a` (2 queries per genre); for a
    # library with N genres that was `2 * N` extra round-trips per
    # `GET /games`. The batch object replaces those with one grouped
    # count + one windowed top-N fetch (2 queries total regardless of
    # N). The partial reads from `@genres_shelf_batch.for(genre)` and
    # falls back to the old code path when the local isn't passed
    # (view-spec render-partial calls hit the fallback so isolation
    # tests stay independent).
    @genres_shelf_batch = Games::GenreShelfBatch.new(genres: @genres_for_shelf)

    # Phase 27 follow-up (2026-05-11) — composite-cover warm-up. Walk
    # each collection slated for the outer shelf and ask the composer
    # to materialize / refresh the on-disk composite (or no-op on a
    # cache hit / 0-1 member layouts). Running it in the controller —
    # once per request, in-line, BEFORE the view renders — guarantees
    # the `_collection_tile.html.erb` partial sees a fresh
    # `composite_cover_checksum` for 2+ member collections instead of
    # falling through to the fallback SVG (P27 reviewer BLOCKER:
    # `Collections::CoverComposer` was built but never invoked).
    Games::PrepareCollectionsForShelf.new.call(@collections_for_shelf)

    # Phase 27 polish (2026-05-11) — the legacy `@genres_shelves`
    # per-genre iteration was retired. The 01c-v2 nested Genres
    # outer shelf at the top of the page (`@genres_for_shelf`) is
    # the single source of truth for genre-grouped tile rows.

    # Phase 27 v2 spec 05 — per-platform shelves retired. The new
    # contract is genres outer shelf → collections outer shelf →
    # per-letter shelves; the legacy per-platform shelves are gone
    # from the page. The platform filter still lives on the 01b
    # filter row's `owned_on=<slug>` token.

    @filter = sanitized_filter
    # Phase 28 §01a — primaries-only by default across every listing
    # partition. `?include_editions=yes` flips the listing to a flat
    # set (every Game row, editions included). Any other value
    # (including `true` / `1` / nil) defaults to primaries-only per
    # the yes/no boundary rule.
    @include_editions = YesNo.from_yes_no(params[:include_editions])
    scope = @include_editions ? Game.all : Game.primaries
    scope = scope.joins(:game_genres).where(game_genres: { genre_id: @filter[:genre_id] }) if @filter[:genre_id]
    scope = scope.where(collection_id: @filter[:collection_id])                            if @filter[:collection_id]

    # Phase 27 §01b — filter row state read from a single CSV param.
    # The query composes AFTER `?genre=` / `?collection=` narrowing
    # (01c) and BEFORE the per-mode partitioning (01d). Unknown tokens
    # are dropped; the contradiction case (`owned, not_owned` together)
    # short-circuits the listing to `Game.none` and renders a muted
    # notice in the filter-row component.
    @filter_tokens         = parse_filter_tokens(params[:filters])
    @dropped_filter_tokens = parse_dropped_tokens(params[:filters])
    @filter_query          = Games::Filter.new(scope: scope, tokens: @filter_tokens)
    @filter_contradiction  = @filter_query.contradiction?
    scope                  = @filter_query.results

    @all_games = scope.order(Arel.sql("release_year DESC NULLS LAST"))

    # Phase 27 v2 spec 05 — letter buckets for the shelves-by-letter
    # layout (now the SOLE listing layout on `/games`).
    #
    # Bucketing rule: first character of `Game.title` uppercased when
    # in `[A-Z]`, otherwise `'#'`. Empty buckets are hidden — only
    # letters that own at least one game render a `<section>`. Within
    # a bucket, games sort by `LOWER(title)`, with `id` as a stable
    # tiebreak. The `#` (digit / symbol) bucket renders LAST, after
    # `Z`, per the spec's pinned decision.
    @letter_buckets = build_letter_buckets(@all_games)

    respond_to do |format|
      format.html
      format.json do
        # Phase 21 — JSON parity. The JSON branch returns the filtered
        # / sorted `@all_games` collection along with the sort+filter
        # echo so the caller can verify what it asked for.
        @json_games = @all_games.order(sort_clause)
        @json_sort  = { key: sanitized_sort_key, dir: sanitized_dir }
      end
    end
  end

  def show
    @game = Game.friendly.find(params[:id])
    # Preserve the request format on the canonical-slug redirect so a
    # `GET /games/42.json` 301s to `/games/the-witness.json`, not
    # `/games/the-witness` (which would 406 the JSON caller).
    return if redirect_to_canonical_slug!(@game) { |g|
      request.format.json? ? game_path(g, format: :json) : game_path(g)
    }

    # show.html.erb reads @game directly; nothing else to set up here.
    respond_to do |format|
      format.html
      format.json { render :show }
    end
  end

  # Phase 14 §1 polish (2026-05-10) — show / edit split. The form
  # that used to live inline on show.html.erb moved to its own
  # `/games/:id/edit` screen so the show page reads as canonical
  # read-only metadata.
  def edit
    @game = Game.friendly.find(params[:id])
  end

  # Phase 28 §01a — local primaries typeahead for the version-parent
  # picker on the game edit page. Returns up to 20 rows. Title-only
  # ILIKE; primaries only (an edition cannot itself parent another
  # edition — architect lean #2 locked). The current row is excluded
  # via `?exclude_id=`.
  #
  # Response shape:
  #
  #   { "results": [ { "id": 123, "title": "Pragmata" }, ... ] }
  def version_parent_search
    q = params[:q].to_s.strip[0, MAX_QUERY_LENGTH]
    exclude_id = params[:exclude_id].to_i
    if q.blank?
      render json: { results: [] }
      return
    end

    scope = Game.primaries
                .where("LOWER(title) ILIKE ?", "%#{Game.sanitize_sql_like(q.downcase)}%")
                .order(:title)
                .limit(VERSION_PARENT_SEARCH_LIMIT)
    scope = scope.where.not(id: exclude_id) if exclude_id.positive?

    render json: { results: scope.map { |g| { id: g.id, title: g.title } } }
  end

  def search
    @query = params[:q].to_s.strip
    if @query.length > MAX_QUERY_LENGTH
      @query = @query[0, MAX_QUERY_LENGTH]
    end

    @results = []
    @search_error = nil
    @took_ms = 0.0
    if @query.present?
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        @results = Igdb::Client.new.search_games(@query, limit: 10)
      rescue Igdb::Client::Error => e
        @search_error = { kind: "upstream_unavailable", message: e.message }
      end
      @took_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)
    end

    respond_to do |format|
      format.html do
        # Legacy HTML branch (Turbo Frame) renders only the partial. The
        # JSON branch returns the structured envelope.
        legacy_error = @search_error.is_a?(Hash) ? "igdb error: #{@search_error[:message]}" : nil
        render partial: "search_results",
               locals: { results: @results, query: @query, search_error: legacy_error }
      end
      format.json { render :search }
    end
  end

  # Phase 27 spec 04 (2026-05-17) — IGDB add-game flow is the SINGLE
  # entry point to creating a game. The legacy "no `igdb_id`" branch
  # that persisted a blank `Game` row with the `"Untitled game"`
  # attribute default is REMOVED. Requests without `igdb_id` return
  # 422 and a flash explaining the new contract.
  #
  # Permit list is exactly `:igdb_id, :title`. The `:title` value
  # comes from the IGDB search-result row's `name` field carried as
  # a hidden form param on the `[add]` `button_to`, and seeds the
  # new game synchronously so the redirect-target's breadcrumb
  # reads as the real IGDB title instead of the `"Untitled game"`
  # default during the in-flight `GameIgdbSync` window. The async
  # job still overwrites with the canonical IGDB record on
  # completion.
  def create
    create_params = params.fetch(:game, {}).permit(:igdb_id, :title)
    igdb_id_param = create_params[:igdb_id]

    if igdb_id_param.blank?
      flash[:alert] = "games can only be added via the IGDB search modal."
      respond_to do |format|
        format.html { redirect_to games_path, status: :see_other }
        format.json { render json: { error: "igdb_id_required" }, status: :unprocessable_content }
      end
      return
    end

    igdb_id = igdb_id_param.to_i
    if igdb_id <= 0
      redirect_to games_path, alert: "igdb id must be a positive integer." and return
    end

    existing = Game.find_by(igdb_id: igdb_id)
    if existing
      redirect_to game_path(existing), alert: "already in your library."
      return
    end

    # Eager title pre-seed: the IGDB search-result row already carries
    # the IGDB-canonical name. Forwarding it as a hidden form param on
    # `[add]` lets us avoid the `"Untitled game"` attribute default
    # during the in-flight window between create and the async sync's
    # completion. Trim + length-guard mirror the column's 255-char
    # validation; blank pre-seeds fall back to the attribute default.
    title_seed = create_params[:title].to_s.strip[0, 255]
    new_attrs = { igdb_id: igdb_id }
    new_attrs[:title] = title_seed if title_seed.present?

    game = Game.new(new_attrs)
    if game.save
      GameIgdbSync.perform_async(game.id)
      redirect_to game_path(game), notice: "added; metadata loading in background."
    else
      redirect_to games_path, alert: "could not add game."
    end
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
    @game = Game.friendly.find(params[:id])
    if @game.resyncing?
      respond_to do |format|
        format.html { redirect_to game_path(@game), notice: "already resyncing." }
        format.json do
          render json: {
            game_id: @game.id,
            resyncing: YesNo.to_yes_no(true),
            error: "already_resyncing"
          }, status: :conflict
        end
      end
      return
    end
    @enqueued_jid = GameIgdbSync.perform_async(@game.id)
    respond_to do |format|
      format.html { redirect_to game_path(@game), notice: "refreshing from igdb…" }
      format.json { render :resync, status: :accepted }
    end
  end

  private

  # Phase 14 §1 — strict local-only allowlist. IGDB-sourced columns
  # smuggled into params are silently dropped (the `params.permit`
  # call only references local-only attributes).
  #
  # Phase 27 §1a — `platform_owned_id` is gone (the column was dropped
  # and ownership now flows through `game_platform_ownerships`). A
  # smuggled `game[platform_owned_id]` value is silently dropped because
  # the permit list no longer references it; the dedicated ownership
  # editor (lands in 01f) is the canonical surface for editing the join.
  def local_only_params
    permitted = params.fetch(:game, {}).permit(
      :played_at,
      :notes,
      :hours_of_footage_manual,
      :version_parent_id,
      :version_title
    )

    # Phase 28 §01a — coerce `version_parent_id` to either an integer
    # or nil. A blank string ("") submitted by the form's hidden input
    # when the user clicks `[detach]` lands as nil so the row becomes
    # a primary again. Non-numeric garbage drops to nil; the model
    # validator rejects invalid pointers with a friendly error.
    if permitted.key?("version_parent_id")
      raw = permitted["version_parent_id"]
      permitted["version_parent_id"] = raw.to_s.strip.empty? ? nil : raw.to_i
    end

    # `version_title`: trim to 100 chars; blank → nil.
    if permitted.key?("version_title")
      raw = permitted["version_title"].to_s.strip[0, 100]
      permitted["version_title"] = raw.empty? ? nil : raw
    end

    permitted
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

  # Phase 14 §3 — `/games?genre=<id>` filter route powers the per-shelf
  # "[see all]" link. Genre id input is an integer; missing /
  # non-positive values are dropped so arbitrary `?genre=evil` strings
  # reduce to "no filter applied".
  #
  # Phase 27 §01c — extends `?genre` to also accept a slug string and
  # adds `?collection=<slug>` for the new Collections shelf. Slug
  # lookups go through ActiveRecord with `find_by`; SQL-unsafe input
  # never reaches the query because the value is bound, and a missing
  # match reduces to "no filter applied" (no row leaks).
  #
  # Phase 27 §1a — the legacy `?platform_owned=<id>` filter is
  # retired here (the `games.platform_owned_id` column it queried is
  # gone). The canonical platform filter moves to 01b's filter row
  # token `owned_on=<slug>`.
  def sanitized_filter
    filter = {}
    genre_id = resolve_genre_id(params[:genre])
    collection_id = resolve_collection_id(params[:collection])
    filter[:genre_id] = genre_id if genre_id&.positive?
    filter[:collection_id] = collection_id if collection_id&.positive?
    filter
  end

  # Accepts a positive integer id (existing `?genre=<id>` contract) or
  # a non-empty string slug (`?genre=<slug>` for the 01c shelf tile).
  # Unknown / blank inputs return nil so the caller skips the filter.
  def resolve_genre_id(raw)
    return nil if raw.blank?
    int = raw.to_i
    return int if int.positive? && raw.to_s == int.to_s
    Genre.where(slug: raw.to_s).limit(1).pick(:id)
  end

  # Accepts a string slug for the 01c collection shelf tile. Unknown
  # / blank inputs return nil. Integer ids are also accepted for
  # symmetry with `genre` though the canonical tile URL uses the slug.
  def resolve_collection_id(raw)
    return nil if raw.blank?
    int = raw.to_i
    return int if int.positive? && raw.to_s == int.to_s
    Collection.where(slug: raw.to_s).limit(1).pick(:id)
  end

  # Phase 27 v2 spec 05 — build the letter-bucket array.
  #
  # Returns an Array of `[letter, [Game, ...]]` tuples in render
  # order (A..Z first, `#` last). Empty buckets are NOT included.
  # The grouping happens in Ruby (not SQL) because the bucket key
  # is a derived value — uppercased first character with a
  # collapse-to-`#` fallback for digits / symbols — and the
  # already-filtered `@all_games` relation is bounded in size by
  # the per-install library cap (spec 05 §"no pagination").
  def build_letter_buckets(scope)
    grouped = scope.to_a.group_by do |game|
      first = game.title.to_s.strip[0]
      if first && first.match?(/[A-Za-z]/)
        first.upcase
      else
        "#"
      end
    end

    grouped.each_value do |games|
      games.sort_by! { |g| [ g.title.to_s.downcase, g.id ] }
    end

    ordered = grouped.keys.sort_by { |letter| letter == "#" ? "{" : letter }
    ordered.map { |letter| [ letter, grouped[letter] ] }
  end
end
