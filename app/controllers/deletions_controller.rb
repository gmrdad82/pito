class DeletionsController < ApplicationController
  before_action :load_items

  # GET /deletions/:type/:ids
  def show
    @cancel_path = cancel_path
  end

  # POST /deletions/:type/:ids
  def create
    @cancel_path = cancel_path

    @operation = BulkOperation.create!(kind: :bulk_delete, status: :pending, started_at: Time.current)
    @items.each do |item|
      @operation.bulk_operation_items.create!(
        target: item,
        target_type: item.class.name,
        target_id: item.id,
        status: :pending
      )
    end

    BulkDeleteJob.perform_in(3.seconds, @operation.id)

    render :progress
  end

  private

  def load_items
    @type = params[:type].to_s
    ids = params[:ids].to_s.split(",").reject(&:blank?)

    @items = case @type
    when "channel" then Channel.where(id: ids).order(title: :asc)
    when "video"   then Video.includes(:channel)
                          .left_joins(:video_stats)
                          .select(
                            "videos.*",
                            "COALESCE(SUM(video_stats.views), 0) AS total_views",
                            "COALESCE(SUM(video_stats.likes), 0) AS total_likes",
                            "COALESCE(SUM(video_stats.comments), 0) AS total_comments",
                            # CAST AS BIGINT is Postgres-portable. MySQL used SIGNED; replaced during Phase 2.
                            "COALESCE(CAST(SUM(video_stats.watch_time_minutes) AS BIGINT), 0) AS total_watch_time"
                          )
                          .where(id: ids)
                          .group("videos.id")
                          .order(title: :asc)
    else
      redirect_to root_path, alert: "unknown type."
      return
    end

    if @items.empty?
      redirect_to cancel_path, alert: "nothing to delete."
    end

    @cancel_path = cancel_path
  end

  def cancel_path
    case @type
    when "channel" then channels_path
    when "video"   then videos_path
    else root_path
    end
  end
end
