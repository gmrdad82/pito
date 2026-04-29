module Mcp
  module Tools
    class GetDashboard < MCP::Tool
      tool_name "get_dashboard"
      description "Get dashboard analytics: summary counts, daily views, views by channel, top videos, and daily engagement (likes/comments). Supports time ranges: 7d, 30d, 90d, 1y, all."

      RANGES = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365, "all" => nil }.freeze

      input_schema(
        type: "object",
        properties: {
          range: { type: "string", enum: %w[7d 30d 90d 1y all], description: "Time range (default: 30d)" }
        },
      )

      annotations(read_only_hint: true)

      def self.call(range: "30d")
        range = "30d" unless RANGES.key?(range)
        days = RANGES[range]
        date_range = days ? (Date.current - days.days)..Date.current : (Date.new(2000)..Date.current)

        daily_views = VideoStat.where(date: date_range).group_by_day(:date).sum(:views)

        views_by_channel = VideoStat.joins(video: :channel)
          .where(date: date_range)
          .group("channels.title")
          .sum(:views)

        top_videos = Video.joins(:video_stats)
          .where(video_stats: { date: date_range })
          .group("videos.id", "videos.title")
          .select("videos.id", "videos.title", "SUM(video_stats.views) AS total_views")
          .order("total_views DESC")
          .limit(10)
          .map { |v| { id: v.id, title: v.title, total_views: v.total_views } }

        daily_engagement = {
          likes: VideoStat.where(date: date_range).group_by_day(:date).sum(:likes),
          comments: VideoStat.where(date: date_range).group_by_day(:date).sum(:comments)
        }

        data = {
          summary: {
            channel_count: Channel.count,
            video_count: Video.count,
            range: range
          },
          daily_views: daily_views,
          views_by_channel: views_by_channel,
          top_videos: top_videos,
          daily_engagement: daily_engagement
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end
    end
  end
end
