class DashboardController < ApplicationController
  RANGES = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365, "all" => nil }.freeze

  def index
    @video_count = Video.count
    @channel_count = Channel.count
    @range = RANGES.key?(params[:range]) ? params[:range] : "30d"

    @daily_views = VideoStat
      .where(date: date_range)
      .group_by_day(:date)
      .sum(:views)

    @views_by_channel = VideoStat
      .joins(video: :channel)
      .where(date: date_range)
      .group("channels.title")
      .group_by_day(:date)
      .sum(:views)

    @top_videos = Video
      .joins(:video_stats)
      .where(video_stats: { date: date_range })
      .group("videos.id", "videos.title")
      .select("videos.id", "videos.title", "SUM(video_stats.views) AS total_views")
      .order("total_views DESC")
      .limit(10)

    @daily_engagement = [
      { name: "likes", data: VideoStat.where(date: date_range).group_by_day(:date).sum(:likes) },
      { name: "comments", data: VideoStat.where(date: date_range).group_by_day(:date).sum(:comments) }
    ]

    respond_to do |format|
      format.html
      format.json { render json: dashboard_json }
    end
  end

  private

  def date_range
    days = RANGES[@range]
    days ? (Date.current - days.days)..Date.current : (Date.new(2000)..Date.current)
  end

  def dashboard_json
    {
      summary: { video_count: @video_count, channel_count: @channel_count, range: @range },
      daily_views: @daily_views,
      views_by_channel: @views_by_channel,
      top_videos: @top_videos.map { |v| { id: v.id, title: v.title, total_views: v.total_views } },
      daily_engagement: @daily_engagement
    }
  end
end
