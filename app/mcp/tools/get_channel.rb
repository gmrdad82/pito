module Mcp
  module Tools
    class GetChannel < MCP::Tool
      tool_name "get_channel"
      description "Get the full detail JSON for a channel: id, channel_url, star, connected, syncing, last_synced_at, timestamps."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Channel ID" }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: true)

      def self.call(id:)
        channel = Channel.find_by(id: id)
        return error_response("channel not found: #{id}") unless channel

        data = ChannelDecorator.new(channel).as_detail_json
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
