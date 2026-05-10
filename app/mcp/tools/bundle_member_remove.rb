module Mcp
  module Tools
    # Phase 14 §3 — remove a Game from a Bundle. Triggers a cover rebuild.
    class BundleMemberRemove < MCP::Tool
      tool_name "bundle_member_remove"
      description "Remove a game from a bundle. Triggers a composite-cover rebuild."

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

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(bundle_id:, game_id:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        bundle = Bundle.find_by(id: bundle_id)
        return error_response("bundle not found: #{bundle_id}") unless bundle
        member = bundle.bundle_members.find_by(game_id: game_id)
        return error_response("game not a member of this bundle.") unless member

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, bundle_id: bundle.id, game_id: game_id,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        member.destroy!
        payload = { bundle_id: bundle.id, game_id: game_id,
                    message: "member removed; cover rebuild queued." }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
