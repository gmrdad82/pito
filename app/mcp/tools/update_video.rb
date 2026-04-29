module Mcp
  module Tools
    class UpdateVideo < MCP::Tool
      tool_name "update_video"
      description "Update an existing video's metadata (title, description, privacy, tags, category, language)."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Video ID" },
          title: { type: "string", description: "New title" },
          description: { type: "string", description: "New description" },
          privacy_status: { type: "string", enum: %w[public_video unlisted private_video], description: "Privacy status" },
          tags: { type: "string", description: "Comma-separated tags" },
          category_id: { type: "string", description: "YouTube category ID" },
          default_language: { type: "string", description: "Language code" }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: false)

      def self.call(id:, **fields)
        video = Video.find_by(id: id)
        return MCP::Tool::Response.new([ { type: "text", text: "video not found: #{id}" } ], error: true) unless video

        attrs = fields.compact
        if attrs.empty?
          return MCP::Tool::Response.new([ { type: "text", text: "no fields to update." } ], error: true)
        end

        if video.update(attrs)
          data = VideoDecorator.new(video.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "video updated.\n#{JSON.pretty_generate(data)}" } ])
        else
          MCP::Tool::Response.new([ { type: "text", text: "couldn't update video: #{video.errors.full_messages.join(', ')}" } ], error: true)
        end
      end
    end
  end
end
