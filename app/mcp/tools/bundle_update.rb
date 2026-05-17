module Mcp
  module Tools
    # Phase 14 §3 / Phase 27 follow-up (2026-05-17) — update a Bundle.
    # `name` is the only mutable attribute (and the only attribute,
    # period, after the 2026-05-17 simplification).
    class BundleUpdate < MCP::Tool
      tool_name "bundle_update"
      description "Update a bundle's name."

      input_schema(
        type: "object",
        properties: {
          id: { type: "string", description: "Bundle slug or integer id (as string)" },
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

        bundle = begin
          Bundle.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
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
