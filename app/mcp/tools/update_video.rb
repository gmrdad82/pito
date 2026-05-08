module Mcp
  module Tools
    class UpdateVideo < MCP::Tool
      tool_name "update_video"
      description "Update star (favorite flag) on a video. Phase 7 Path A2: Video is a thin YouTube-reference record; metadata fields (title, description, privacy_status, tags, category, language) are gone."

      input_schema(
        type: "object",
        properties: {
          id:   { type: "integer", description: "Video ID" },
          star: { type: "string", enum: [ "yes", "no" ], description: "Star (favorite) flag — 'yes' or 'no'" }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, star: nil, **_extras)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_WRITE)
        return scope_err if scope_err

        video = Video.find_by(id: id)
        return error_response("video not found: #{id}") unless video

        attrs = {}
        unless star.nil?
          return error_response("star must be 'yes' or 'no' (got #{star.inspect})") unless YesNo.yes_no?(star)
          attrs[:star] = YesNo.from_yes_no(star)
        end

        if attrs.empty?
          return error_response("no fields to update.")
        end

        if video.update(attrs)
          data = VideoDecorator.new(video.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "video updated.\n#{JSON.pretty_generate(data)}" } ])
        else
          error_response("couldn't update video: #{video.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
