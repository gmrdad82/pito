class DashboardController < ApplicationController
  # Home (/) — serves the xterm.js web shell for HTML requests, JSON for API.
  allow_anonymous :index, :sidebar, :channel_analytics

  def index
    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end

  # REMOVED: cable handles status bar now

  # GET /analytics/channel/:id — time-series data for ASCII chart rendering
  def channel_analytics
    channel = Channel.find(params[:id])
    dailies = channel.channel_dailies.order(date: :desc).limit(90).map do |d|
      { date: d.date.to_s, views: d.views, watch_time_minutes: d.estimated_minutes_watched }
    end
    render json: {
      channel_url: channel.channel_url,
      dailies: dailies.reverse,
      trend: compute_trend(dailies)
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

  def compute_trend(dailies)
    return "flat" if dailies.size < 14

    recent  = dailies.last(7).sum { |d| d[:views] } / 7.0
    earlier = dailies.first(dailies.size - 7).last(7).sum { |d| d[:views] } / 7.0

    return "flat" if earlier.zero? && recent.zero?
    return "up"   if earlier.zero?

    pct = ((recent - earlier) / earlier.to_f) * 100
    if pct > 5
      "up"
    elsif pct < -5
      "down"
    else
      "flat"
    end
  end

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
