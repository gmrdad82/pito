class DashboardController < ApplicationController
  # Home (/) — serves the xterm.js web shell for HTML requests, JSON for API.
  allow_anonymous :index, :sidebar, :status

  def index
    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end

  # GET /status.json — live Sidekiq + connection status for status bar
  def status
    stats = Sidekiq::Stats.new
    render json: {
      connected: true,
      sidekiq: {
        busy: stats.workers_size,
        enqueued: stats.enqueued,
        retry: stats.retry_size,
        dead: stats.dead_size,
        scheduled: stats.scheduled_size
      },
      timestamp: Time.current.iso8601
    }
  end

  # GET /sidebar.json — sidebar data for both web and TUI clients
  def sidebar
    render json: {
      channels: channel_stats,
      recent_videos: recent_videos,
      upcoming_games: upcoming_games
    }
  end

  private

  def dashboard_json
    {
      video_count:   Video.count,
      channel_count: Channel.count,
      footage_count: Footage.count
    }
  end

  def channel_stats
    Channel.all.map do |ch|
      {
        channel_url: ch.channel_url,
        star: ch.star,
        video_count: ch.videos.count,
        total_views: ch.videos.sum(:view_count)
      }
    end
  end

  def recent_videos
    Video.order(created_at: :desc).limit(10).map do |v|
      {
        youtube_video_id: v.youtube_video_id,
        title: v.title,
        views: v.view_count,
        channel_url: v.channel&.channel_url
      }
    end
  end

  def upcoming_games
    Game.where.not(release_date: nil)
        .where("release_date > ?", Time.current)
        .order(release_date: :asc)
        .limit(10)
        .map do |g|
      {
        title: g.title,
        release_date: g.release_date&.strftime("%Y-%m-%d")
      }
    end
  end
end
