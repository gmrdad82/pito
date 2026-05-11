module Mcp
  module Tools
    # Phase 23 §23a — MCP tool: read the open VideoDiff for a video.
    # Returns the same JSON shape `GET /videos/:slug/diff.json` returns
    # so the CLI lane and the Claude desktop / Claude mobile lanes
    # consume the same contract.
    class VideoDiffShow < MCP::Tool
      tool_name "video_diff_show"
      description "Show the open YouTube-vs-Pito diff for a video. Returns the differing fields + payload + writable-field set. Use `apply_diff` to resolve."

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

        diff = video.open_diff
        unless diff
          payload = {
            video_id: video.id,
            video_slug: video.to_param,
            open: false,
            message: "no open diff for this video"
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        data = {
          open: true,
          diff_id: diff.id,
          video_id: video.id,
          video_slug: video.to_param,
          youtube_video_id: video.youtube_video_id,
          title: video.title,
          detected_at: diff.detected_at&.iso8601,
          fields: diff.fields,
          payload: diff.payload,
          writable_fields: Youtube::DiffComputer::WRITABLE_FIELDS,
          display_only_fields: Youtube::DiffComputer::DISPLAY_ONLY_FIELDS
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
