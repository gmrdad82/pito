module Mcp
  module Tools
    class GetChannel < MCP::Tool
      tool_name "get_channel"
      description "Get the full detail JSON for a channel: id, channel_url, star, last_synced_at, video_count, timestamps."

      # Phase 20 — friendly URLs. `id` accepts either a slug (UC-id /
      # `channel-<id>` fallback) or an integer id as a string. Schema is
      # `string` so the JSON-RPC input validator accepts both shapes.
      input_schema(
        type: "object",
        properties: {
          id: {
            type: "string",
            description: "Channel slug (UC-id) or integer id (as string)"
          }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: true)

      def self.call(id:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        channel = begin
          Channel.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
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
