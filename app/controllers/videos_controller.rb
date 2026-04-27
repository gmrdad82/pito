class VideosController < ApplicationController
  def index
    @saved_views = SavedView.videos.ordered
    @videos = Video.includes(:channel)
      .left_joins(:video_stats)
      .select(
        "videos.*",
        "COALESCE(SUM(video_stats.views), 0) AS total_views",
        "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
        "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
        "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS SIGNED), 0) AS total_watch_time"
      )
      .group("videos.id")
      .order(published_at: :desc)
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
    params.require(:video).permit(:title, :description, :privacy_status, :category_id, :default_language, :made_for_kids, :tags)
  end
end
