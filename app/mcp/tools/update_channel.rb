module Mcp
  module Tools
    class UpdateChannel < MCP::Tool
      tool_name "update_channel"
      description "Update star (favorite flag) on a channel. The `connected` flag is OAuth-managed and cannot be altered via MCP. The channel_url is locked once set and cannot be changed via this tool."

      input_schema(
        type: "object",
        properties: {
          id:   { type: "integer", description: "Channel ID" },
          star: { type: "string", enum: [ "yes", "no" ], description: "Star (favorite) flag — 'yes' or 'no'" }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      CONNECTED_NOT_ALLOWED = "Cannot alter `connected` via MCP. The connected flag reflects OAuth state and is managed by the web UI's connect/disconnect action only."

      def self.call(id:, star: nil, **extras)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_WRITE)
        return scope_err if scope_err

        # Defense in depth: if the client managed to bypass additionalProperties:
        # false and pass `connected:` anyway, reject the entire call. This must
        # come before any update so that star is NOT applied when connected is
        # also present (atomic rejection).
        if extras.key?(:connected) || extras.key?("connected")
          return error_response(CONNECTED_NOT_ALLOWED)
        end

        # Defense in depth: if the client managed to pass channel_url through
        # additionalProperties, refuse explicitly rather than silently dropping.
        if extras.key?(:channel_url) || extras.key?("channel_url")
          return error_response("channel_url cannot be changed once set.")
        end

        channel = Channel.find_by(id: id)
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
