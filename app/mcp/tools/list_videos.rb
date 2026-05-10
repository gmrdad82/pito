module Mcp
  module Tools
    class ListVideos < MCP::Tool
      tool_name "list_videos"
      description "List videos with stats (views, likes, comments, watch time) plus title and privacy_status. Optionally filter by channel_id."

      input_schema(
        type: "object",
        properties: {
          channel_id: { type: "string", description: "Filter by channel slug (UC-id) or integer id (as string, optional)" },
          limit: { type: "integer", description: "Max results (default 50, max 200)" }
        },
      )

      annotations(read_only_hint: true)

      def self.call(channel_id: nil, limit: 50)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        limit = [ [ limit.to_i, 1 ].max, 200 ].min

        scope = Video.includes(:channel)
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
          .order(created_at: :desc)
          .limit(limit)

        if channel_id.present?
          channel = begin
            Channel.friendly.find(channel_id)
          rescue ActiveRecord::RecordNotFound
            nil
          end
          scope = scope.where(channel_id: channel.id) if channel
        end

        data = scope.map { |v| VideoDecorator.new(v).as_summary_json }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end
    end
  end
end
