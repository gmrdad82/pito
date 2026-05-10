module Mcp
  module Tools
    # Phase 14 §3 — flip `is_primary` on a single VideoGameLink row.
    class VideoLinkSetPrimary < MCP::Tool
      tool_name "video_link_set_primary"
      description "Flip is_primary on a video↔game/bundle link. is_primary is 'yes'/'no'."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "VideoGameLink id" },
          is_primary: { type: "string", enum: [ "yes", "no" ] },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id", "is_primary" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, is_primary:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)
        return error_response("is_primary must be 'yes' or 'no' (got #{is_primary.inspect})") unless YesNo.yes_no?(is_primary)

        link = VideoGameLink.find_by(id: id)
        return error_response("link not found: #{id}") unless link

        new_value = YesNo.from_yes_no(is_primary)

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, id: link.id,
                      changes: { is_primary: { old: YesNo.to_yes_no(link.is_primary),
                                               new: is_primary } },
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        if link.update(is_primary: new_value)
          payload = { id: link.id, is_primary: YesNo.to_yes_no(link.is_primary),
                      message: "link updated." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't update link: #{link.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
