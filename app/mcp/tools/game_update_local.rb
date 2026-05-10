module Mcp
  module Tools
    # Phase 14 §3 — update local-only Game fields. IGDB-sourced columns
    # are NOT writable through this tool (use `game_resync` to re-pull).
    class GameUpdateLocal < MCP::Tool
      tool_name "game_update_local"
      description "Update local-only game fields (platform_owned_id, played_at, notes, hours_of_footage_manual)."

      # Phase 20 — friendly URLs. `id` accepts slug or integer-id string.
      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Game slug (igdb_slug) or integer id (as string)" },
          platform_owned_id: { type: [ "integer", "null" ] },
          played_at: { type: [ "string", "null" ], description: "ISO date (YYYY-MM-DD) or null." },
          notes: { type: [ "string", "null" ] },
          hours_of_footage_manual: { type: [ "integer", "null" ] },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, confirm: "no", **input)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        game = begin
          Game.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("game not found: #{id}") unless game

        attrs = {}
        attrs[:platform_owned_id]       = input[:platform_owned_id]       if input.key?(:platform_owned_id)
        attrs[:played_at]               = input[:played_at]               if input.key?(:played_at)
        attrs[:notes]                   = input[:notes]                   if input.key?(:notes)
        attrs[:hours_of_footage_manual] = input[:hours_of_footage_manual] if input.key?(:hours_of_footage_manual)

        return error_response("no fields to update.") if attrs.empty?

        if YesNo.from_yes_no(confirm) == false
          changes = attrs.transform_values do |new_v|
            { new: new_v }
          end
          payload = { preview: true, id: game.id, changes: changes,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        if game.update(attrs)
          payload = { id: game.id, message: "game updated.",
                      title: game.title }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't update game: #{game.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
