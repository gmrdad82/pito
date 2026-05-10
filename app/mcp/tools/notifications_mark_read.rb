module Mcp
  module Tools
    # Phase 16 §3 — `notifications_mark_read` MCP tool.
    #
    # Bulk mark-read. Accepts `ids: [<int>, ...]`. Master decision
    # 2026-05-10 open-question #3: NO `confirm: yes/no` requirement
    # because mark-read is non-destructive. CLAUDE.md's two-step
    # pattern is for destructive / significant actions.
    #
    # Returns `{marked_read: <count>, ids: [...], not_found_ids: [...]}`
    # in a single call. Idempotent: re-running on already-read rows
    # leaves their `in_app_read_at` untouched (we only update unread
    # rows). Unknown ids are reported in `not_found_ids` and
    # otherwise ignored (graceful no-op per CLAUDE.md / test sweep).
    class NotificationsMarkRead < MCP::Tool
      tool_name "notifications_mark_read"
      description "mark one or more notifications as read."

      input_schema(
        type: "object",
        properties: {
          ids: {
            type: "array",
            items: { type: "integer" },
            description: "Notification IDs to mark as read."
          }
        },
        required: [ "ids" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: false)

      def self.call(ids: nil, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        unless ids.is_a?(Array)
          return error_response("ids must be an array of integers.")
        end

        # Sanitize: drop nils, blanks, and entries that fail strict
        # integer coercion. A malformed UUID-style string here is a
        # client error — surface it rather than silently dropping.
        sanitized = []
        bad = []
        ids.each do |raw|
          if raw.is_a?(Integer)
            sanitized << raw
          elsif raw.is_a?(String) && raw.match?(/\A\d+\z/)
            sanitized << raw.to_i
          else
            bad << raw
          end
        end

        if bad.any?
          return error_response("ids must be integers; got #{bad.inspect}")
        end

        sanitized.uniq!

        if sanitized.empty?
          payload = { marked_read: 0, ids: [], not_found_ids: [] }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        existing = Notification.where(id: sanitized).pluck(:id)
        not_found = sanitized - existing

        marked_count = Notification.where(id: existing).unread.count
        Notification.where(id: existing).unread.update_all(in_app_read_at: Time.current) if marked_count.positive?

        broadcast_badge_replace

        payload = {
          marked_read: marked_count,
          ids: existing,
          not_found_ids: not_found
        }
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
        Rails.logger.warn("NotificationsMarkRead: badge broadcast failed: #{e.class}: #{e.message}")
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
