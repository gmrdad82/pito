module Mcp
  module Tools
    class CreateVideo < MCP::Tool
      tool_name "create_video"
      description "Create a new video under a channel. A local youtube_video_id is auto-generated."

      input_schema(
        type: "object",
        properties: {
          title: { type: "string", description: "Video title (required)" },
          channel_id: { type: "integer", description: "Channel ID (required)" },
          description: { type: "string", description: "Video description" },
          privacy_status: { type: "string", enum: %w[public_video unlisted private_video], description: "Privacy status" },
          tags: { type: "string", description: "Comma-separated tags" },
          category_id: { type: "string", description: "YouTube category ID" },
          default_language: { type: "string", description: "Language code (e.g. en, es)" }
        },
        required: [ "title", "channel_id" ]
      )

      annotations(read_only_hint: false)

      def self.call(title:, channel_id:, description: nil, privacy_status: nil, tags: nil, category_id: nil, default_language: nil)
        video = Video.new(
          title: title,
          channel_id: channel_id,
          description: description,
          privacy_status: privacy_status,
          tags: tags,
          category_id: category_id,
          default_language: default_language
        )
        video.youtube_video_id = "local_#{SecureRandom.hex(8)}"

        if video.save
          data = VideoDecorator.new(video).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "video created.\n#{JSON.pretty_generate(data)}" } ])
        else
          MCP::Tool::Response.new([ { type: "text", text: "couldn't create video: #{video.errors.full_messages.join(', ')}" } ], error: true)
        end
      end
    end
  end
end
