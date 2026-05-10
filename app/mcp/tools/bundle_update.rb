module Mcp
  module Tools
    # Phase 14 §3 — update Bundle. Only `name` is mutable post-create
    # (§2 master decision — `bundle_type` and `igdb_source_*` are
    # immutable).
    class BundleUpdate < MCP::Tool
      tool_name "bundle_update"
      description "Update a bundle's name. bundle_type and igdb_source_* are immutable."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer" },
          name: { type: "string" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "id", "name" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(id:, name:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        bundle = Bundle.find_by(id: id)
        return error_response("bundle not found: #{id}") unless bundle

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, id: bundle.id,
                      changes: { name: { old: bundle.name, new: name } },
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        if bundle.update(name: name)
          payload = { id: bundle.id, name: bundle.name, message: "bundle updated." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't update bundle: #{bundle.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
