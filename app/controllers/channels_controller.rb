class ChannelsController < ApplicationController
  include FriendlyRedirect
  # Phase 24 — Google management UI moved off /settings/youtube and onto
  # /channels. ChannelsController owns the OAuth request-phase entry
  # point (`POST /channels/connect_google`); the concern's
  # `stash_youtube_connect_intent` + `redirect_target_for_intent` route
  # the callback back to `/channels`.
  include YoutubeConnectionOauthRedirect

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  ALLOWED_SORTS = {
    "id" => "channels.id",
    "created_at" => "channels.created_at",
    "updated_at" => "channels.updated_at",
    "last_synced_at" => "channels.last_synced_at",
    "channel_url" => "channels.channel_url",
    "starred" => "channels.star",
    # 2026-05-11 ergonomics — surface the cached `subscriber_count` and
    # `video_count` columns as sortable keys. Both columns are nullable
    # (pre-sync rows render the muted em-dash); Postgres default NULL
    # ordering — NULLS LAST on asc, NULLS FIRST on desc — matches the
    # convention the rest of the index uses for `last_synced_at`.
    "subscriber_count" => "channels.subscriber_count",
    "video_count" => "channels.video_count"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  # Phase 37 Wave A1 — mocked `/channels` dashboard shell.
  #
  # The legacy pane workspace (saved views, sort/dir, star filter,
  # picker prefetch) is dropped FROM THIS ACTION ONLY. Real data
  # wiring returns in Wave B once the layout is signed off.
  # `Channels::MockData.channels` feeds the avatar shelf via
  # `@channels`. JSON branch is preserved for CLI / MCP callers and
  # still serves the real DB rows decorated by `ChannelDecorator` so
  # downstream surfaces don't regress on the layout-iteration phase.
  # See `docs/orchestration/handoff-2026-05-19-channels-and-live-updates.md`
  # §"Implementation plan" → Wave A1.
  #
  # Phase 37 Wave A2 — chip URL wiring + Basics totals plumbing.
  #
  # The HTML branch now READS the three filter params the chip row
  # already toggles via `FilterChipComponent` (csv mode):
  #
  #   * `?channels=` — comma-separated channel ids. Drives which
  #     `Channels::MockData.channels` entries land in `@channels` and,
  #     transitively, in the ID-card shelf + the Basics row. Sentinel
  #     handling per the spec:
  #       - param missing entirely        → render ALL channels
  #       - param present-but-empty (`?channels=`) → render ZERO
  #         channels (user unchecked everything; matches the chip
  #         visual state "0 of 6 checked")
  #       - unknown id (e.g. `?channels=999`) → silently dropped
  #   * `?windows=` — time-window selection (`7d`, `28d`, `3m`,
  #     `365d`, `alltime`). Parsed and exposed as
  #     `@selected_windows` for downstream waves; no render code
  #     consumes it yet.
  #   * `?calendar=` — year/month selection. Parsed and exposed as
  #     `@selected_calendar` for downstream waves; no render code
  #     consumes it yet.
  #
  # Spec: `docs/plans/beta/37-channels-revamp/specs/02-wave-a2-chip-wiring-basics.md`.
  ALLOWED_WINDOW_VALUES = %w[7d 28d 3m 365d alltime].freeze

  def index
    respond_to do |format|
      format.html do
        @selected_windows = parse_csv_filter_param(params[:windows])
          &.select { |v| ALLOWED_WINDOW_VALUES.include?(v) } || []
        @selected_calendar = parse_csv_filter_param(params[:calendar]) || []

        selected_channel_ids = parse_csv_filter_param(params[:channels])
        all_channels = Channels::MockData.channels
        @channels = if selected_channel_ids.nil?
          all_channels
        else
          all_channels.select { |c| selected_channel_ids.include?(c[:id].to_s) }
        end
      end
      format.json do
        records = Channel.all.order(sort_clause)
        render json: records.map { |c| ChannelDecorator.new(c).as_summary_json }
      end
    end
  end

  def show
    @channel = Channel.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@channel) { |c| channel_path(c) }

    @max_panes = max_panes
    @available_channels = Channel.where.not(id: @channel.id).order(:channel_url)
    # Phase 24 — Google management panel on the channel show page.
    # Exposes the connection that owns this specific channel so the
    # partial renders email / scopes / last-authorized / reauth state.
    @youtube_connection = @channel.youtube_connection

    # 2026-05-11 — channel show page restructure. The videos block is
    # now a /videos-style table (not a pane), capped at 30 rows,
    # starred-first then latest. Aggregates mirror VideosController#index
    # so cells reuse the same helpers (total_views, total_likes, ...).
    @channel_videos_total = @channel.videos.count
    @channel_videos = @channel.videos
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      # Qualify columns — the `left_joins(:video_stats)` adds a
      # `video_stats.created_at` to scope, so unqualified `created_at`
      # / `star` raises PG::AmbiguousColumn.
      .order(Arel.sql("videos.star DESC, COALESCE(videos.published_at, videos.created_at) DESC"))
      .limit(30)

    respond_to do |format|
      format.html
      format.json { render json: ChannelDecorator.new(@channel).as_detail_json }
    end
  end

  # Phase 24 — POST /channels/connect_google
  #
  # Request-phase entry point for the Google OAuth dance, moved from
  # `Settings::YoutubeController#connect`. Stash the intent so the
  # callback routes back to `/channels`. `params[:account] == "new"`
  # appends `prompt=select_account consent` so Google renders the
  # account picker / Brand-Account switcher rather than silently
  # reusing the most-recently-used Google account.
  # `include_granted_scopes=true` keeps the consent additive so an
  # existing grant on the picked account is not downgraded.
  def connect_google
    stash_youtube_connect_intent
    target = if params[:account].to_s == "new"
               "/auth/google_oauth2?" \
                 "prompt=#{ERB::Util.url_encode('select_account consent')}" \
                 "&include_granted_scopes=true"
    else
               "/auth/google_oauth2"
    end
    redirect_to target, allow_other_host: false, status: :see_other
  end

  def destroy
    @channel = Channel.friendly.find(params[:id])
    @channel.destroy
    respond_to do |format|
      format.html { redirect_to channels_path, notice: "channel deleted." }
      format.json { head :no_content }
    end
  end

  # GET /channels/:id/videos(.json)
  #
  # Returns the videos belonging to the given channel. Used by the pito CLI
  # to populate per-channel video lists. JSON shape mirrors
  # VideosController#index so the same Rust `Video` struct decodes either
  # response.
  def videos
    @channel = Channel.friendly.find(params[:id])
    @videos = @channel.videos
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(created_at: :desc)

    respond_to do |format|
      format.html { redirect_to channel_path(@channel) }
      format.json { render json: @videos.map { |v| VideoDecorator.new(v).as_summary_json } }
    end
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      if ids.first
        # Phase 20 — friendly URLs. Resolve the input (slug or integer
        # id) to the canonical record so the redirect target is the
        # slug URL.
        record = begin
          Channel.friendly.find(ids.first)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        redirect_to record ? channel_path(record) : channels_path
      else
        redirect_to channels_path
      end
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    # Phase 20 — friendly URLs. Pane keys arrive as either integer ids
    # (legacy bookmarks) or UC-id slugs. `friendly.find` resolves both;
    # we swallow `RecordNotFound` so a missing pane shows up as nil and
    # the view renders a placeholder instead of 500ing the row.
    @panes = @current_ids.map do |key|
      Channel.friendly.find(key)
    rescue ActiveRecord::RecordNotFound
      nil
    end
    @resolved_pane_ids = @panes.compact.map(&:id)
    @pane_title_length = pane_title_length
    @available_channels = Channel.where.not(id: @resolved_pane_ids).order(:channel_url) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :channels, url: CGI.unescape(request.fullpath))
  end

  private

  # Phase 37 Wave A2 — shared CSV filter param parser for `?channels=`,
  # `?windows=`, `?calendar=`.
  #
  # Returns `nil` for missing params (sentinel: "no filter applied,
  # render default"). Returns an Array<String> otherwise — empty array
  # for present-but-empty (`?channels=`), populated array for csv
  # values. The two states differ so `?channels=` can render zero
  # cards instead of falling back to "render all".
  def parse_csv_filter_param(raw)
    return nil if raw.nil?

    raw.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def max_panes
    # Phase 29 (settings refactor) — read from `config/pito.yml` via
    # `Rails.application.config.x.pito.max_panes` (loaded once at boot
    # by `config/initializers/pito_config.rb`).
    Rails.application.config.x.pito.max_panes
  end

  def pane_title_length
    # Phase 29 (settings refactor) — see `max_panes` above.
    Rails.application.config.x.pito.pane_title_length
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
    Arel.sql("#{column} #{direction}")
  end
end
