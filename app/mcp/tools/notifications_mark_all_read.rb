module Mcp
  module Tools
    # Phase 16 §3 — `notifications_mark_all_read` MCP tool.
    #
    # Marks every unread notification (install-wide) as read. No
    # params. Master decision 2026-05-10 open-question #3: NO
    # `confirm: yes/no` requirement — mark-read is non-destructive.
    #
    # Returns `{marked_read: <count>}`.
    class NotificationsMarkAllRead < MCP::Tool
      tool_name "notifications_mark_all_read"
      description "mark all unread notifications as read."

      input_schema(
        type: "object",
        properties: {},
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: false)

      def self.call(**_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        marked_count = Notification.unread.count
        Notification.unread.update_all(in_app_read_at: Time.current) if marked_count.positive?

        broadcast_badge_replace

        payload = { marked_read: marked_count }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.broadcast_badge_replace
        Turbo::StreamsChannel.broadcast_replace_to(
          "notifications_badge",
          target: "notifications_badge",
          partial: "notifications/badge",
          locals: { unread_count: Notification.unread.count }
        )
      rescue StandardError => e
        Rails.logger.warn("NotificationsMarkAllRead: badge broadcast failed: #{e.class}: #{e.message}")
      end
    end
  end
end
