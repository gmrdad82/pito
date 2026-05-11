module Mcp
  module Tools
    # Phase 28 §01a — `games_list` MCP tool.
    #
    # Paginated read of the local Game library. Defaults to PRIMARIES
    # ONLY (`version_parent_id IS NULL`). Pass `include_editions: "yes"`
    # for the flat list. The yes/no boundary rule (CLAUDE.md hard rule)
    # rejects anything other than `"yes"` / `"no"` with a clear error.
    #
    # Response rows include `version_parent_id`, `version_title`, and
    # `editions_count` (the count of children for a primary, 0 for an
    # edition).
    class GamesList < MCP::Tool
      tool_name "games_list"
      description "list pito games. defaults to primaries only; pass include_editions: \"yes\" for the flat list."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      input_schema(
        type: "object",
        properties: {
          include_editions: {
            type: "string",
            enum: %w[yes no],
            description: "\"yes\" → flat list including editions; \"no\" / omitted → primaries only."
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

      def self.call(include_editions: nil, page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        # yes/no boundary. nil / blank → "no" (primaries only).
        unless include_editions.nil? || include_editions.to_s.empty?
          unless YesNo.yes_no?(include_editions)
            return error_response("include_editions must be \"yes\" or \"no\" (got #{include_editions.inspect})")
          end
        end
        flat = YesNo.from_yes_no(include_editions)

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        scope = flat ? Game.all : Game.primaries
        scope = scope.order(:title)
        total = scope.count

        # Pre-load edition counts so primary rows can render an
        # `editions_count` without N+1 queries.
        rows = scope.offset((page - 1) * per_page).limit(per_page).to_a
        primary_ids = rows.select(&:primary?).map(&:id)
        edition_counts = primary_ids.any? ? Game.where(version_parent_id: primary_ids).group(:version_parent_id).count : {}

        payload = {
          include_editions: YesNo.to_yes_no(flat),
          games: rows.map { |g| payload_for(g, edition_counts) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: total.zero? ? 0 : ((total + per_page - 1) / per_page)
          }
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.payload_for(game, edition_counts)
        {
          id: game.id,
          title: game.title,
          igdb_id: game.igdb_id,
          igdb_slug: game.igdb_slug,
          release_year: game.release_year,
          igdb_rating: game.igdb_rating&.to_f,
          version_parent_id: game.version_parent_id,
          version_title: game.version_title,
          editions_count: game.primary? ? (edition_counts[game.id] || 0) : 0
        }
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
