module Mcp
  module Tools
    # Phase 14 §3 — read-only Bundle search by name.
    class BundleSearch < MCP::Tool
      tool_name "bundle_search"
      description "Search bundles by name (substring, case-insensitive). Limit 25."

      input_schema(
        type: "object",
        properties: {
          q: { type: "string", description: "Name fragment (or empty for top 25 by updated_at)." }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(q: "")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        query = q.to_s.strip
        scope = Bundle.all
        scope = scope.where("name ILIKE ?", "%#{Bundle.sanitize_sql_like(query)}%") if query.present?

        rows = scope.order(updated_at: :desc).limit(25)
        payload = rows.map do |b|
          {
            id: b.id,
            name: b.name,
            bundle_type: b.bundle_type,
            igdb_source_type: b.igdb_source_type,
            igdb_source_id: b.igdb_source_id,
            member_count: b.bundle_members.size
          }
        end
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
