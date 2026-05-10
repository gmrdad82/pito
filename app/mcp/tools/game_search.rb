module Mcp
  module Tools
    # Phase 14 §3 — read-only local Game search.
    # Returns up to 25 local Game rows whose titles match the query
    # (case-insensitive substring). For IGDB live search use
    # `igdb_search`.
    class GameSearch < MCP::Tool
      tool_name "game_search"
      description "Search the local Game library by title (substring, case-insensitive). Limit 25."

      input_schema(
        type: "object",
        properties: {
          q: { type: "string", description: "Title fragment" }
        },
        required: [ "q" ],
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(q:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        query = q.to_s.strip
        return error_response("q must not be blank.") if query.empty?

        games = Game.where("title ILIKE ?", "%#{Game.sanitize_sql_like(query)}%")
                    .order(:title)
                    .limit(25)

        payload = games.map do |g|
          {
            id: g.id,
            title: g.title,
            igdb_id: g.igdb_id,
            release_year: g.release_year,
            igdb_rating: g.igdb_rating
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
