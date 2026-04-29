module Mcp
  module Tools
    class CreateChannel < MCP::Tool
      tool_name "create_channel"
      description "Create a new channel. A local youtube_channel_id is auto-generated."

      input_schema(
        type: "object",
        properties: {
          title: { type: "string", description: "Channel title (required)" },
          description: { type: "string", description: "Channel description" }
        },
        required: [ "title" ]
      )

      annotations(read_only_hint: false)

      def self.call(title:, description: nil)
        channel = Channel.new(title: title, description: description)
        channel.youtube_channel_id = "local_#{SecureRandom.hex(8)}"

        if channel.save
          data = ChannelDecorator.new(channel).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "channel created.\n#{JSON.pretty_generate(data)}" } ])
        else
          MCP::Tool::Response.new([ { type: "text", text: "couldn't create channel: #{channel.errors.full_messages.join(', ')}" } ], error: true)
        end
      end
    end
  end
end
