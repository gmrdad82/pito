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

    # Group by channel id (Phase B: schema no longer has channels.title).
    # Series labels become "channel #<id>" — readable and stable.
    raw_views_by_channel = VideoStat
      .joins(video: :channel)
      .where(date: date_range)
      .group("channels.id")
      .group_by_day(:date)
      .sum(:views)

    @views_by_channel = raw_views_by_channel.each_with_object({}) do |((channel_id, date), value), out|
      out[[ "channel ##{channel_id}", date ]] = value
    end

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
      video_count: @video_count,
      channel_count: @channel_count,
      range: @range,
      daily_views: hash_to_tuples(@daily_views),
      views_by_channel: views_by_channel_tuples(@views_by_channel),
      top_videos: @top_videos.map { |v| { title: v.title, views: v.total_views.to_i } },
      daily_engagement: {
        likes: hash_to_tuples(VideoStat.where(date: date_range).group_by_day(:date).sum(:likes)),
        comments: hash_to_tuples(VideoStat.where(date: date_range).group_by_day(:date).sum(:comments))
      }
    }
  end

  # Convert a Groupdate `{ Date/Time => count }` hash into an array of
  # `[iso_date_string, count]` tuples. The pito CLI's Rust decoder expects
  # `Vec<(String, u64)>` for these series.
  def hash_to_tuples(hash)
    hash.map do |key, value|
      label = key.respond_to?(:iso8601) ? key.to_date.iso8601 : key.to_s
      [ label, value.to_i ]
    end
  end

  # Convert the Groupdate `{ ["channel #N", date] => count }` hash into a
  # nested array shape:
  #   [ ["channel #N", [ [date_string, views], ... ]], ... ]
  # Matches the Rust `Vec<(String, Vec<(String, u64)>)>` decoder.
  def views_by_channel_tuples(hash)
    grouped = hash.each_with_object({}) do |((label, date), value), out|
      out[label] ||= []
      iso = date.respond_to?(:iso8601) ? date.to_date.iso8601 : date.to_s
      out[label] << [ iso, value.to_i ]
    end
    grouped.map { |label, series| [ label, series ] }
  end
end
