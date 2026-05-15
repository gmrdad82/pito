module Mcp
  module Tools
    # Phase 7.5 §11g — MCP tool: paginated read of the channel change
    # history audit trail. Mirrors the JSON branch of
    # `GET /channels/:slug/history.json` (Phase 21 list-endpoint
    # contract: `changes` array + `pagination` object).
    #
    # Read-only — the underlying `channel_change_logs` table is
    # append-only at the model layer. `app` scope (per ADR 0004 —
    # the only non-`dev` scope).
    class ChannelChangesList < MCP::Tool
      tool_name "channel_changes_list"
      description "List title / handle change-history rows for a channel, newest first. Paginated."

      PER_PAGE = 50

      input_schema(
        type: "object",
        properties: {
          channel: {
            type: "string",
            description: "Channel slug (UC-id portion of channel_url) or numeric id (as string)."
          },
          page: {
            type: "integer",
            minimum: 1,
            description: "1-based page number (default 1)."
          }
        },
        required: [ "channel" ]
      )

      annotations(read_only_hint: true)

      def self.call(channel: nil, page: 1, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("channel is required") if channel.nil? || channel.to_s.strip.empty?

        record = begin
          Channel.friendly.find(channel)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("channel not found: #{channel}") unless record

        page  = [ page.to_i, 1 ].max
        scope = record.channel_change_logs.order(changed_at: :desc)

        total = scope.count
        rows  = scope.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

        payload = {
          changes: rows.map { |log| row_payload(log) },
          pagination: {
            page: page,
            per_page: PER_PAGE,
            total: total,
            total_pages: [ ((total + PER_PAGE - 1) / PER_PAGE), 1 ].max
          }
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.row_payload(log)
        user = log.changed_by_user
        {
          id: log.id,
          field: log.field,
          old_value: log.old_value,
          new_value: log.new_value,
          changed_at: log.changed_at.utc.iso8601,
          changed_by: user ? { id: user.id, username: user.username } : nil
        }
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
