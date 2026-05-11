module Mcp
  module Tools
    # Phase 7.5 §11i — MCP tool: read the open ChannelDiff for a
    # channel. Mirrors `video_diff_show` (Phase 23 §23a). Returns the
    # same JSON shape `GET /channels/:slug/diff.json` returns so the
    # CLI lane and the Claude desktop / Claude mobile lanes consume
    # the same contract.
    class ChannelDiffShow < MCP::Tool
      tool_name "channel_diff_show"
      description "Show the open YouTube-vs-Pito diff for a channel. Returns the differing fields + field_diffs + writable-field set. Use `channel_diff_apply` to resolve."

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

        diff = channel.open_channel_diff
        unless diff
          payload = {
            channel_id: channel.id,
            channel_slug: channel.to_param,
            open: false,
            message: "no open diff for this channel"
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        data = {
          open: true,
          diff_id: diff.id,
          channel_id: channel.id,
          channel_slug: channel.to_param,
          channel_url: channel.channel_url,
          title: channel.title,
          detected_at: diff.detected_at&.iso8601,
          fields: diff.fields,
          field_diffs: diff.field_diffs,
          writable_fields: Channels::DiffApply::BRANDING_PUSH_FIELDS +
                           [ Channels::DiffApply::HANDLE_FIELD ],
          unsupported_pito_fields: Channels::DiffApply::UNSUPPORTED_PITO_FIELDS
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
