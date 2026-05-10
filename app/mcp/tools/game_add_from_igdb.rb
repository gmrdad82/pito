module Mcp
  module Tools
    # Phase 14 §3 — add a Game by IGDB id. Two-step `confirm: yes/no`.
    # On `confirm: yes` a Game row is created (or returned if already
    # present) and `GameIgdbSync` is enqueued to hydrate metadata.
    class GameAddFromIgdb < MCP::Tool
      tool_name "game_add_from_igdb"
      description "Add a game by its IGDB id. Background-syncs metadata after create."

      input_schema(
        type: "object",
        properties: {
          igdb_id: { type: "integer", description: "IGDB game id" },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "set confirm: 'yes' to perform; 'no' to preview."
          }
        },
        required: [ "igdb_id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(igdb_id:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        igdb_id = igdb_id.to_i
        return error_response("igdb_id must be a positive integer.") unless igdb_id.positive?

        if YesNo.from_yes_no(confirm) == false
          existing = Game.find_by(igdb_id: igdb_id)
          payload = {
            preview: true,
            igdb_id: igdb_id,
            existing_local_id: existing&.id,
            hint: "set confirm: 'yes' to perform; 'no' to preview."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        existing = Game.find_by(igdb_id: igdb_id)
        if existing
          payload = { id: existing.id, igdb_id: existing.igdb_id, message: "already in library." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        game = Game.new(igdb_id: igdb_id)
        if game.save
          GameIgdbSync.perform_async(game.id)
          payload = { id: game.id, igdb_id: igdb_id, enqueued: true,
                      message: "added; metadata loading in background." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't add game: #{game.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
