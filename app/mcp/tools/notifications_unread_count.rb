module Mcp
  module Tools
    # Phase 16 §3 — `notifications_unread_count` MCP tool.
    #
    # Returns the install-wide unread count. Shape:
    # `{count: <int>}`. No params. Per master decision 2026-05-10
    # open-question #7: NO cache for v1; the partial unique index on
    # `in_app_read_at IS NULL` keeps the COUNT(*) cheap.
    class NotificationsUnreadCount < MCP::Tool
      tool_name "notifications_unread_count"
      description "return the install-wide count of unread notifications."

      input_schema(
        type: "object",
        properties: {},
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(**_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        payload = { count: Notification.unread.count }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end
    end
  end
end
