module Mcp
  module Tools
    # Phase 14 §3 / Phase 27 follow-up (2026-05-17) — create a new
    # Bundle. After the 2026-05-17 simplification a bundle has exactly
    # one attribute: `name`. The legacy `bundle_type`, `igdb_source_type`,
    # `igdb_source_id` inputs are gone.
    class BundleCreate < MCP::Tool
      tool_name "bundle_create"
      description "Create a bundle. Bundles are simple named groupings of games."

      input_schema(
        type: "object",
        properties: {
          name: { type: "string" },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "name" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(name:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, name: name,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        bundle = Bundle.new(name: name)

        if bundle.save
          payload = { id: bundle.id, name: bundle.name,
                      message: "bundle created." }
          MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        else
          error_response("couldn't create bundle: #{bundle.errors.full_messages.join(', ')}")
        end
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
