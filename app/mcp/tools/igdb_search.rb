module Mcp
  module Tools
    # Phase 14 §3 — IGDB live search proxy. Read-only thin wrapper
    # around `Igdb::Client#search_games` so Claude Mobile can find an
    # IGDB id without leaving the conversation. Returns IGDB hits with
    # their `id`, `name`, `slug`, and `release_year` (when known).
    #
    # Phase 14 §1 polish (2026-05-10) — `include_editions: yes/no`
    # opt-in to disable the default "main entries" category filter
    # (see `Igdb::Client::DEFAULT_SEARCH_CATEGORIES`). MCP I/O uses
    # `"yes"` / `"no"` strings per CLAUDE.md hard rule; we coerce to
    # the underlying boolean before handing off to the client.
    class IgdbSearch < MCP::Tool
      tool_name "igdb_search"
      description "Search IGDB live for games by title. Read-only proxy; returns IGDB ids."

      input_schema(
        type: "object",
        properties: {
          q: { type: "string" },
          limit: { type: "integer" },
          include_editions: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "q" ],
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(q:, limit: 10, include_editions: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        query = q.to_s.strip
        return error_response("q must not be blank.") if query.empty?

        capped = limit.to_i.clamp(1, 25)

        coerced_flag = coerce_yes_no(include_editions)
        return error_response("include_editions must be 'yes' or 'no'.") if coerced_flag.nil?

        begin
          hits = Igdb::Client.new.search_games(query, limit: capped, include_editions: coerced_flag)
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

      def self.coerce_yes_no(value)
        case value.to_s.strip.downcase
        when "yes" then true
        when "no", "" then false
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
