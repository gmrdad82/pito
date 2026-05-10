module Mcp
  module Tools
    # Phase 14 §3 — destroy a Game. Cascades through join tables
    # (`game_genres`, `game_platforms`, `game_developers`,
    # `game_publishers`, `bundle_members`, `video_game_links`).
    class GameDestroy < MCP::Tool
      tool_name "game_destroy"
      description "Destroy a game. Cascades through join tables (genres, platforms, bundles, video links)."

      # Phase 20 — friendly URLs. `id` accepts slug (`igdb_slug`) or
      # integer id as a string.
      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Game slug (igdb_slug) or integer id (as string)" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

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

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, id: game.id, title: game.title,
                      videos_linked: game.video_game_links.count,
                      bundles_member_of: game.bundles.count,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        title = game.title
        game.destroy!
        payload = { id: id, title: title, message: "game destroyed." }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
