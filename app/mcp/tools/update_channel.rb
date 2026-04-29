module Mcp
  module Tools
    class UpdateChannel < MCP::Tool
      tool_name "update_channel"
      description "Update an existing channel's title or description."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Channel ID" },
          title: { type: "string", description: "New title" },
          description: { type: "string", description: "New description" }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: false)

      def self.call(id:, title: nil, description: nil)
        channel = Channel.find_by(id: id)
        return MCP::Tool::Response.new([ { type: "text", text: "channel not found: #{id}" } ], error: true) unless channel

        attrs = {}
        attrs[:title] = title if title
        attrs[:description] = description if description

        if attrs.empty?
          return MCP::Tool::Response.new([ { type: "text", text: "no fields to update." } ], error: true)
        end

        if channel.update(attrs)
          data = ChannelDecorator.new(channel.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "channel updated.\n#{JSON.pretty_generate(data)}" } ])
        else
          MCP::Tool::Response.new([ { type: "text", text: "couldn't update channel: #{channel.errors.full_messages.join(', ')}" } ], error: true)
        end
      end
    end
  end
end
