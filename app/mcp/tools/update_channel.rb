module Mcp
  module Tools
    class UpdateChannel < MCP::Tool
      tool_name "update_channel"
      description "Update star (favorite flag) on a channel. Connection state is OAuth-managed via /settings/youtube and cannot be altered via MCP. The channel_url is locked once set and cannot be changed via this tool."

      # Phase 20 — friendly URLs. `id` accepts a slug or integer id.
      input_schema(
        type: "object",
        properties: {
          id:   { type: "string", description: "Channel slug (UC-id) or integer id (as string)" },
          star: { type: "string", enum: [ "yes", "no" ], description: "Star (favorite) flag — 'yes' or 'no'" }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, star: nil, **extras)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        # Defense in depth: if the client managed to pass channel_url through
        # additionalProperties, refuse explicitly rather than silently dropping.
        if extras.key?(:channel_url) || extras.key?("channel_url")
          return error_response("channel_url cannot be changed once set.")
        end

        channel = begin
          Channel.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("channel not found: #{id}") unless channel

        attrs = {}
        unless star.nil?
          return error_response("star must be 'yes' or 'no' (got #{star.inspect})") unless YesNo.yes_no?(star)
          attrs[:star] = YesNo.from_yes_no(star)
        end

        if attrs.empty?
          return error_response("no fields to update.")
        end

        if channel.update(attrs)
          data = ChannelDecorator.new(channel.reload).as_detail_json
          MCP::Tool::Response.new([ { type: "text", text: "channel updated.\n#{JSON.pretty_generate(data)}" } ])
        else
          error_response("couldn't update channel: #{channel.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
