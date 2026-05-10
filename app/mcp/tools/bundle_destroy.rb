module Mcp
  module Tools
    # Phase 14 §3 — destroy a Bundle. Cascades through `bundle_members`
    # and `video_game_links`. The composite cover file is swept by
    # `Bundle#before_destroy`.
    class BundleDestroy < MCP::Tool
      tool_name "bundle_destroy"
      description "Destroy a bundle. Cascades through members + video links + on-disk composite cover."

      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Bundle slug or integer id (as string)" },
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

        bundle = begin
          Bundle.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
        return error_response("bundle not found: #{id}") unless bundle

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, id: bundle.id, name: bundle.name,
                      member_count: bundle.bundle_members.size,
                      video_links: bundle.video_game_links.size,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        name = bundle.name
        bundle.destroy!
        payload = { id: id, name: name, message: "bundle destroyed." }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
