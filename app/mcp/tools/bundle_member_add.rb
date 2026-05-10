module Mcp
  module Tools
    # Phase 14 §3 — add a Game to a Bundle. `BundleCoverBuild` is
    # enqueued from `BundleMember`'s after_create_commit callback.
    class BundleMemberAdd < MCP::Tool
      tool_name "bundle_member_add"
      description "Add a game to a bundle. Triggers a composite-cover rebuild."

      input_schema(
        type: "object",
        properties: {
          bundle_id: { type: "integer" },
          game_id: { type: "integer" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "bundle_id", "game_id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(bundle_id:, game_id:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        bundle = Bundle.find_by(id: bundle_id)
        return error_response("bundle not found: #{bundle_id}") unless bundle
        game = Game.find_by(id: game_id)
        return error_response("game not found: #{game_id}") unless game

        if bundle.bundle_members.exists?(game_id: game.id)
          return error_response("game already a member of this bundle.")
        end

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, bundle_id: bundle.id, game_id: game.id,
                      bundle_name: bundle.name, game_title: game.title,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        member = bundle.bundle_members.create(game: game)
        if member.persisted?
          payload = { id: member.id, bundle_id: bundle.id, game_id: game.id,
                      message: "member added; cover rebuild queued." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't add member: #{member.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
