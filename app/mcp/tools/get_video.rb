module Mcp
  module Tools
    class GetVideo < MCP::Tool
      tool_name "get_video"
      description "Get detailed video info: id, youtube_video_id, channel, star, last_synced_at, and last 30 days of daily stats. Phase 7 Path A2: metadata fields (title, description, tags, etc.) are gone."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Video ID" }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: true)

      def self.call(id:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = Video.find_by(id: id)
        return error_response("video not found: #{id}") unless video

        data = VideoDecorator.new(video).as_detail_json
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
