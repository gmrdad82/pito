module Mcp
  module Tools
    class ListChannels < MCP::Tool
      tool_name "list_channels"
      description "List all YouTube channels with subscriber counts, video counts, and view totals. Returns summary data for each channel."

      annotations(read_only_hint: true)

      def self.call
        channels = Channel.left_joins(:videos)
          .select("channels.*", "COUNT(videos.id) AS videos_count")
          .group("channels.id")
          .order(title: :asc)

        data = channels.map { |c| ChannelDecorator.new(c).as_summary_json }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end
    end
  end
end
