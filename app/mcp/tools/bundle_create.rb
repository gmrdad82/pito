module Mcp
  module Tools
    # Phase 14 §3 — create a new Bundle.
    # `bundle_type` is immutable post-create (per §2 master decision).
    class BundleCreate < MCP::Tool
      tool_name "bundle_create"
      description "Create a bundle. bundle_type is immutable; igdb_source_* required for non-custom types."

      BUNDLE_TYPES = %w[series collection genre custom].freeze
      IGDB_SOURCE_TYPES = %w[franchise source_collection source_genre].freeze

      input_schema(
        type: "object",
        properties: {
          name: { type: "string" },
          bundle_type: { type: "string", enum: BUNDLE_TYPES },
          igdb_source_type: { type: [ "string", "null" ], enum: IGDB_SOURCE_TYPES + [ nil ] },
          igdb_source_id: { type: [ "integer", "null" ] },
          confirm: { type: "string", enum: [ "yes", "no" ] }
        },
        required: [ "name", "bundle_type" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false)

      def self.call(name:, bundle_type:, igdb_source_type: nil, igdb_source_id: nil, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})") unless YesNo.yes_no?(confirm)
        return error_response("bundle_type must be one of #{BUNDLE_TYPES.inspect}.") unless BUNDLE_TYPES.include?(bundle_type)

        igdb_source_id_val = igdb_source_id.present? ? igdb_source_id.to_i : nil

        if YesNo.from_yes_no(confirm) == false
          payload = { preview: true, name: name, bundle_type: bundle_type,
                      igdb_source_type: igdb_source_type,
                      igdb_source_id: igdb_source_id_val,
                      hint: "set confirm: 'yes' to perform; 'no' to preview." }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
        end

        attrs = {
          name: name,
          bundle_type: bundle_type,
          igdb_source_type: igdb_source_type.presence,
          igdb_source_id: igdb_source_id_val
        }
        bundle = Bundle.new(attrs)

        if bundle.save
          payload = { id: bundle.id, name: bundle.name,
                      bundle_type: bundle.bundle_type,
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
