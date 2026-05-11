module Mcp
  module Tools
    # Phase 28 §01a — `game_show` MCP tool.
    #
    # Read a single Game row. The response carries
    # `version_parent_id`, `version_title`, plus an `editions` array of
    # `{ id, title, igdb_slug, version_title }` objects (empty for an
    # edition). Callers resolve the parent via a second `game_show`
    # call if they need the parent's full row.
    class GameShow < MCP::Tool
      tool_name "game_show"
      description "Read a single pito Game by id or igdb_slug. Returns version_parent_id, version_title, and an editions array."

      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Game id (integer as string) or igdb_slug." }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(id:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        identifier = id.to_s.strip
        return error_response("id must not be blank.") if identifier.empty?

        game = lookup(identifier)
        return error_response("game not found: #{identifier}") if game.nil?

        editions = game.primary? ? game.editions.order(:title).map { |e| edition_payload(e) } : []
        payload = {
          id: game.id,
          title: game.title,
          igdb_id: game.igdb_id,
          igdb_slug: game.igdb_slug,
          release_year: game.release_year,
          igdb_rating: game.igdb_rating&.to_f,
          version_parent_id: game.version_parent_id,
          version_title: game.version_title,
          editions: editions
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.lookup(identifier)
        if identifier.match?(/\A\d+\z/)
          Game.find_by(id: identifier.to_i) || Game.friendly.find(identifier)
        else
          Game.friendly.find(identifier)
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def self.edition_payload(edition)
        {
          id: edition.id,
          title: edition.title,
          igdb_slug: edition.igdb_slug,
          version_title: edition.version_title
        }
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
