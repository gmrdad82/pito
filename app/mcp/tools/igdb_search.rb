module Mcp
  module Tools
    # Phase 14 §3 — IGDB live search proxy. Read-only thin wrapper
    # around `Igdb::Client#search_games` so Claude Mobile can find an
    # IGDB id without leaving the conversation. Returns IGDB hits with
    # their `id`, `name`, `slug`, and `release_year` (when known).
    class IgdbSearch < MCP::Tool
      tool_name "igdb_search"
      description "Search IGDB live for games by title. Read-only proxy; returns IGDB ids."

      input_schema(
        type: "object",
        properties: {
          q: { type: "string" },
          limit: { type: "integer" }
        },
        required: [ "q" ],
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(q:, limit: 10)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        query = q.to_s.strip
        return error_response("q must not be blank.") if query.empty?

        capped = limit.to_i.clamp(1, 25)

        begin
          hits = Igdb::Client.new.search_games(query, limit: capped)
        rescue Igdb::Client::Error => e
          return error_response("igdb error: #{e.message}")
        end

        payload = Array(hits).map do |g|
          {
            igdb_id: g["id"],
            name: g["name"],
            slug: g["slug"],
            first_release_date: g["first_release_date"]
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
