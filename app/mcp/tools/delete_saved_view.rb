module Mcp
  module Tools
    class DeleteSavedView < MCP::Tool
      tool_name "delete_saved_view"
      description "Delete a saved workspace view by ID."

      input_schema(
        type: "object",
        properties: {
          id: { type: "integer", description: "Saved view ID" }
        },
        required: [ "id" ]
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(id:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_WRITE)
        return scope_err if scope_err

        sv = SavedView.find_by(id: id)
        return MCP::Tool::Response.new([ { type: "text", text: "saved view not found: #{id}" } ], error: true) unless sv

        name = sv.name
        sv.destroy!

        MCP::Tool::Response.new([ { type: "text", text: "deleted saved view: #{name}" } ])
      end
    end
  end
end
