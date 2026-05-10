module Mcp
  module Tools
    # Phase 16 §3 — `notifications_list` MCP tool.
    #
    # Paginated read of the install-wide notification stream.
    # Returns `NotificationFormatter::Mcp.payload_for(...)` rows
    # (per Spec 02). `read` is the string `"yes"` / `"no"`
    # (CLAUDE.md hard rule: external booleans are yes/no strings).
    #
    # `unread` filter input is the same yes/no string convention.
    # `kind` and `severity` are optional plain string filters keyed
    # against the model's enum value sets; an unknown value is
    # silently ignored (graceful degrade — matches the controller).
    #
    # Master decision 2026-05-10 #13: tool description verbatim.
    class NotificationsList < MCP::Tool
      tool_name "notifications_list"
      description "list pito notifications, optionally filtered by unread/kind/severity. paginated."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      input_schema(
        type: "object",
        properties: {
          unread: {
            type: "string",
            enum: %w[yes no],
            description: "Filter by unread state. \"yes\" = only unread, \"no\" = only read, omit = all."
          },
          kind: {
            type: "string",
            description: "Filter by notification kind (e.g. sync_error)."
          },
          severity: {
            type: "string",
            description: "Filter by severity (info, success, warn, urgent)."
          },
          page: {
            type: "integer",
            description: "1-based page number (default 1)."
          },
          per_page: {
            type: "integer",
            description: "Results per page (default 25, max 100)."
          }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(unread: nil, kind: nil, severity: nil, page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        scope = Notification.all
        scope = apply_unread_filter(scope, unread)
        scope = scope.by_kind(kind) if kind.present? && Notification.kinds.key?(kind.to_s)
        scope = scope.where(severity: severity) if severity.present? && Notification.severities.key?(severity.to_s)
        scope = scope.order(created_at: :desc)

        total = scope.count
        rows  = scope.offset((page - 1) * per_page).limit(per_page)

        payload = {
          notifications: rows.map { |n| NotificationFormatter::Mcp.payload_for(n) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: total.zero? ? 0 : ((total + per_page - 1) / per_page)
          }
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.apply_unread_filter(scope, unread)
        return scope if unread.nil? || unread.to_s.empty?
        return scope unless YesNo.yes_no?(unread)

        YesNo.from_yes_no(unread) ? scope.unread : scope.read
      end
    end
  end
end
