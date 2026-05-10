class VideosController < ApplicationController
  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON requests so the HTML form path keeps
  # its authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # Phase 12 — re-introduce sortable columns dropped during Path A2.
  ALLOWED_SORTS = {
    "id" => "videos.id",
    "title" => "videos.title",
    "created_at" => "videos.created_at",
    "updated_at" => "videos.updated_at",
    "last_synced_at" => "videos.last_synced_at",
    "published_at" => "videos.published_at",
    "privacy_status" => "videos.privacy_status",
    "starred" => "videos.star"
  }.freeze
  ALLOWED_DIRS = %w[asc desc].freeze
  DEFAULT_SORT = "created_at"
  DEFAULT_DIR = "desc"

  PRIVACY_VALUES_FOR_PUBLISH = %w[public unlisted].freeze

  before_action :load_video, only: %i[
    show edit update destroy stats
    pre_publish_checklist publish schedule
  ]

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
    @max_panes = max_panes
    @available_videos = Video.where.not(id: @video.id).order(created_at: :desc).limit(50)

    respond_to do |format|
      format.html
      format.json { render json: VideoDecorator.new(@video).as_detail_json }
    end
  end

  def edit
    @projects = Project.order(:name)
  end

  def update
    if smuggled_publish_state?
      return render_smuggle_error
    end

    # Form sends `tags_csv` as a comma-separated string; translate
    # before VideoPolicy.permit so the writable subset stays declared
    # in one place.
    raw_video_params = params.fetch(:video, {}).to_unsafe_h.with_indifferent_access
    if raw_video_params.key?(:tags_csv)
      csv = raw_video_params.delete(:tags_csv).to_s
      tags = csv.split(",").map(&:strip).reject(&:blank?)
      raw_video_params[:tags] = tags
    end
    attrs = VideoPolicy.permit(ActionController::Parameters.new(raw_video_params))

    if @video.update(attrs)
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video updated." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      respond_to do |format|
        format.html do
          @projects = Project.order(:name)
          render :edit, status: :unprocessable_content
        end
        format.json { render json: { errors: @video.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def pre_publish_checklist
    @target_action = params[:target_action].to_s == "schedule" ? "schedule" : "publish"
    render partial: "videos/pre_publish_modal",
           locals: { video: @video, target_action: @target_action }
  end

  def publish
    perms = VideoPolicy.permit_publish(params.fetch(:video, {}))
    error = validate_publish(perms, @video)
    if error
      return render_publish_error(error)
    end

    target = perms[:target_privacy_status].to_s
    @video.assign_attributes(
      pre_publish_game_ok: yes_no_attr(perms[:pre_publish_game_ok]),
      pre_publish_age_ok: yes_no_attr(perms[:pre_publish_age_ok]),
      pre_publish_paid_promotion_ok: yes_no_attr(perms[:pre_publish_paid_promotion_ok]),
      pre_publish_end_screen_ok: yes_no_attr(perms[:pre_publish_end_screen_ok]),
      pre_publish_checked_at: Time.current,
      privacy_status: target.to_sym,
      published_at: @video.published_at || Time.current
    )

    if @video.save
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video published." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      render_publish_error(@video.errors.full_messages.join(", "))
    end
  end

  def schedule
    perms = VideoPolicy.permit_schedule(params.fetch(:video, {}))
    error = validate_schedule(perms, @video)
    if error
      return render_publish_error(error, target_action: "schedule")
    end

    @video.assign_attributes(
      pre_publish_game_ok: yes_no_attr(perms[:pre_publish_game_ok]),
      pre_publish_age_ok: yes_no_attr(perms[:pre_publish_age_ok]),
      pre_publish_paid_promotion_ok: yes_no_attr(perms[:pre_publish_paid_promotion_ok]),
      pre_publish_end_screen_ok: yes_no_attr(perms[:pre_publish_end_screen_ok]),
      pre_publish_checked_at: Time.current,
      publish_at: parsed_publish_at(perms[:publish_at]),
      privacy_status: :private
    )

    if @video.save
      respond_to do |format|
        format.html { redirect_to video_path(@video), notice: "video scheduled." }
        format.json { render json: VideoDecorator.new(@video.reload).as_detail_json }
      end
    else
      render_publish_error(@video.errors.full_messages.join(", "), target_action: "schedule")
    end
  end

  def destroy
    @video.destroy
    respond_to do |format|
      format.html { redirect_to videos_path, notice: "video deleted." }
      format.json { head :no_content }
    end
  end

  # GET /videos/:id/stats(.json)
  def stats
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
    @available_videos = Video.where.not(id: @current_ids).order(created_at: :desc).limit(50) if @panes.compact.size < @max_panes
    @saved_view = SavedView.find_by(kind: :videos, url: CGI.unescape(request.fullpath))
  end

  private

  def load_video
    @video = Video.find(params[:id])
  end

  def max_panes
    (AppSetting.get("max_panes") || ENV.fetch("MAX_PANES", 3)).to_i
  end

  def pane_title_length
    (AppSetting.get("pane_title_length") || ENV.fetch("PANE_TITLE_LENGTH", 14)).to_i
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

  def video_stat_json(stat)
    {
      date: stat.date.iso8601,
      views: stat.views.to_i,
      likes: stat.likes.to_i,
      comments: stat.comments.to_i,
      watch_time_minutes: stat.watch_time_minutes.to_f
    }
  end

  # The `update` action MUST NOT change privacy_status / publish_at.
  # Those are publish-flow / schedule-flow paths only. A submitted
  # value here means a malicious or buggy caller is attempting to
  # smuggle a publish-state transition past the checklist.
  def smuggled_publish_state?
    fields = params.fetch(:video, {})
    fields.key?(:privacy_status) || fields.key?("privacy_status") ||
      fields.key?(:publish_at) || fields.key?("publish_at")
  end

  def render_smuggle_error
    msg = "use [ publish ] or [ schedule ] to change privacy_status or publish_at."
    respond_to do |format|
      format.html do
        @projects = Project.order(:name)
        @video.errors.add(:base, msg)
        render :edit, status: :unprocessable_content
      end
      format.json { render json: { errors: [ msg ] }, status: :unprocessable_content }
    end
  end

  def validate_publish(perms, video)
    %i[pre_publish_game_ok pre_publish_age_ok
       pre_publish_paid_promotion_ok pre_publish_end_screen_ok].each do |k|
      return "#{k} must be 'yes'" unless YesNo.from_yes_no(perms[k])
    end
    target = perms[:target_privacy_status].to_s
    return "target_privacy_status is required" if target.blank?
    unless PRIVACY_VALUES_FOR_PUBLISH.include?(target)
      return "target_privacy_status must be 'public' or 'unlisted'"
    end
    unless video.privacy_private?
      return "only private videos can be published"
    end
    nil
  end

  def validate_schedule(perms, video)
    %i[pre_publish_game_ok pre_publish_age_ok
       pre_publish_paid_promotion_ok pre_publish_end_screen_ok].each do |k|
      return "#{k} must be 'yes'" unless YesNo.from_yes_no(perms[k])
    end
    return "publish_at is required" if perms[:publish_at].blank?
    parsed = parsed_publish_at(perms[:publish_at])
    return "publish_at must be a valid ISO 8601 timestamp" if parsed.nil?
    return "publish_at must be in the future" if parsed <= Time.current
    unless video.privacy_private?
      return "only private videos can be scheduled"
    end
    nil
  end

  def render_publish_error(message, target_action: "publish")
    respond_to do |format|
      format.html do
        flash.now[:alert] = message
        @target_action = target_action
        render partial: "videos/pre_publish_modal",
               locals: { video: @video, target_action: target_action, error: message },
               status: :unprocessable_content
      end
      format.json do
        render json: { errors: [ message ] }, status: :unprocessable_content
      end
    end
  end

  # Form params arrive as either ActionController::Parameters strings or
  # raw values. Boundary discipline maps "yes" / "no" → boolean.
  def yes_no_attr(value)
    YesNo.from_yes_no(value)
  end

  def parsed_publish_at(value)
    return nil if value.blank?
    Time.iso8601(value.to_s)
  rescue ArgumentError
    begin
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
