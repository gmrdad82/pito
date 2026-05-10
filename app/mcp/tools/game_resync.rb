module Mcp
  module Tools
    # Phase 14 §3 — re-sync an existing Game from IGDB.
    class GameResync < MCP::Tool
      tool_name "game_resync"
      description "Re-pull IGDB-sourced fields for a game. Local-only fields survive."

      # Phase 20 — friendly URLs. `id` accepts slug or integer-id string.
      input_schema(
        type: "object",
        properties: {
          id:      { type: "string", description: "Game slug (igdb_slug) or integer id (as string)" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        game = begin
          Game.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("game not found: #{id}") unless game
        return error_response("game has no igdb_id; use game_add_from_igdb instead.") if game.igdb_id.blank?

        if YesNo.from_yes_no(confirm) == false
          payload = {
            preview: true,
            id: game.id,
            igdb_id: game.igdb_id,
            current_synced_at: game.igdb_synced_at&.iso8601,
            hint: "set confirm: 'yes' to perform; 'no' to preview."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        GameIgdbSync.perform_async(game.id)
        payload = { id: game.id, igdb_id: game.igdb_id, enqueued: true,
                    message: "refreshing from igdb…" }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
