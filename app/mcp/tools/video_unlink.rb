module Mcp
  module Tools
    # Phase 14 §3 — bulk unlink. Takes a list of `video_game_link` ids.
    # Bulk-as-foundation per CLAUDE.md hard rule: a single-id list is
    # legal and is the same surface as the bulk path.
    class VideoUnlink < MCP::Tool
      tool_name "video_unlink"
      description "Remove one or more video↔game/bundle links by their ids."

      input_schema(
        type: "object",
        properties: {
          ids: {
            type: "array",
            items: { type: "integer" },
            minItems: 1
          },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "ids" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(ids:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        id_list = Array(ids).map(&:to_i).uniq.reject(&:zero?)
        return error_response("ids must not be empty.") if id_list.empty?

        links = VideoGameLink.where(id: id_list).to_a
        not_found = id_list - links.map(&:id)

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true,
                      to_remove: links.map { |l| { id: l.id, link_type: l.link_type,
                                                   video_id: l.video_id,
                                                   game_id: l.game_id,
                                                   bundle_id: l.bundle_id } },
                      not_found: not_found,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        removed = 0
        links.each do |l|
          l.destroy
          removed += 1
        end
        payload = { removed: removed, not_found: not_found,
                    message: "removed #{removed} link#{'s' if removed != 1}." }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
