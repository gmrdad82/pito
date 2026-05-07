class VideosController < ApplicationController
  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Server-side sort allowlist consumed by `#index`. Mirrors
  # `ChannelsController::ALLOWED_SORTS` so the index view's link-style
  # column headers can request `?sort=<key>&dir=<asc|desc>` and the
  # controller resolves the key to a vetted SQL fragment. Default sort
  # stays `published_at DESC` (most-recent-first) to match the prior
  # hard-coded order. The JSON endpoint also benefits from honoring
  # caller-supplied sort.
  ALLOWED_SORTS = {
    "id" => "videos.id",
    "created_at" => "videos.created_at",
    "updated_at" => "videos.updated_at",
    "published_at" => "videos.published_at",
    "title" => "videos.title"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "published_at"
  DEFAULT_DIR = "desc"

  def index
    @saved_views = SavedView.videos.ordered
    @videos = Video.includes(:channel)
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        # CAST AS BIGINT is Postgres-portable. MySQL used SIGNED; replaced during Phase 2.
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(sort_clause)
    @sort = sanitized_sort_key
    @dir = sanitized_dir
    @max_panes = max_panes

    respond_to do |format|
      format.html
      format.json { render json: @videos.map { |v| VideoDecorator.new(v).as_summary_json } }
    end
  end

  def show
    @video = Video.find(params[:id])
    @max_panes = max_panes
    @available_videos = Video.where.not(id: @video.id).order(title: :asc).limit(50)

    respond_to do |format|
      format.html
      format.json { render json: VideoDecorator.new(@video).as_detail_json }
    end
  end

  def new
    @video = Video.new
  end

  def create
    @video = Video.new(video_params)
    @video.youtube_video_id ||= "local_#{SecureRandom.hex(8)}"
    if @video.save
      redirect_to video_path(@video), notice: "video created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @video = Video.find(params[:id])
  end

  def update
    @video = Video.find(params[:id])
    if @video.update(video_params)
      redirect_to video_path(@video), notice: "video updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # GET /videos/:id/stats(.json)
  #
  # Returns the per-day VideoStat rows for the video as a JSON array. Used by
  # the pito CLI to render per-video stats charts. The shape matches the Rust
  # `VideoStat` struct: date, views, likes, comments, watch_time_minutes.
  def stats
    @video = Video.find(params[:id])
    @stats = @video.video_stats.order(date: :desc)

    respond_to do |format|
      format.html { redirect_to video_path(@video) }
      format.json do
        payload = @stats.map { |s| video_stat_json(s) }
        render json: payload
      end
    end
  end

  def panes
    ids = params[:ids].to_s.split(/[\s,+]+/).reject(&:blank?)

    if ids.size <= 1
      redirect_to ids.first ? video_path(ids.first) : videos_path
      return
    end

    @max_panes = max_panes
    @current_ids = ids.first(@max_panes)
    @panes = @current_ids.map { |id| Video.find_by(id: id) }
    @pane_title_length = pane_title_length
    @available_videos = Video.where.not(id: @current_ids).order(title: :asc).limit(50) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :videos, url: CGI.unescape(request.fullpath))
  end

  private

  def max_panes
    (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end

  def pane_title_length
    (AppSetting.get("pane_title_length") || ENV.fetch("PANE_TITLE_LENGTH", 14)).to_i
  end

  def video_params
    params.require(:video).permit(:title, :description, :privacy_status, :category_id, :default_language, :made_for_kids, :tags, :channel_id)
  end

  def sanitized_sort_key
    ALLOWED_SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  def sanitized_dir
    requested = params[:dir]&.downcase
    ALLOWED_DIRS.include?(requested) ? requested : DEFAULT_DIR
  end

  def sort_clause
    # Both fragments are derived from frozen allowlists (ALLOWED_SORTS /
    # ALLOWED_DIRS); they never contain user input. The local-variable
    # binding mirrors `ChannelsController#sort_clause` and
    # `ProjectsController#sort_clause` so Brakeman's SQL check resolves the
    # literals through the allowlist constants.
    column = ALLOWED_SORTS[params[:sort]] || ALLOWED_SORTS[DEFAULT_SORT]
    direction = ALLOWED_DIRS.include?(params[:dir]&.downcase) ? params[:dir].downcase : DEFAULT_DIR
    Arel.sql("#{column} #{direction}")
  end

  # Per-day stat shape consumed by the pito CLI (Rust `VideoStat` struct).
  # We coerce numerics explicitly so JSON encoding is stable across DB
  # adapters that may return BigDecimal or string values.
  def video_stat_json(stat)
    {
      date: stat.date.iso8601,
      views: stat.views.to_i,
      likes: stat.likes.to_i,
      comments: stat.comments.to_i,
      watch_time_minutes: stat.watch_time_minutes.to_f
    }
  end
end
