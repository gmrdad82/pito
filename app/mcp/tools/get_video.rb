module Mcp
  module Tools
    class GetVideo < MCP::Tool
      tool_name "get_video"
      description "Get detailed video info: id, youtube_video_id, channel, title, description, tags, category_id, privacy_status, publish_at, published_at, made_for_kids, synthetic_media, pre-publish checklist state, and last 30 days of daily stats."

      # Phase 20 — friendly URLs. `id` accepts either a slug
      # (`youtube_video_id`) or an integer id as a string.
      input_schema(
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "Video slug (youtube_video_id) or integer id (as string)"
          }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: true)

      def self.call(id:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        video = begin
          Video.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
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
