module Mcp
  module Tools
    class CreateSavedView < MCP::Tool
      tool_name "create_saved_view"
      description "Save a workspace view (pane layout) for quick access. Provide the kind (channels/videos), a name, and the pane URL with IDs."

      input_schema(
        type: "object",
        properties: {
          kind: { type: "string", enum: %w[channels videos], description: "View kind" },
          name: { type: "string", description: "Display name for the saved view" },
          ids: {
            type: "array",
            items: { type: "integer" },
            description: "Array of channel or video IDs for the pane layout"
          }
        },
        required: [ "kind", "name", "ids" ]
      )

      annotations(read_only_hint: false)

      def self.call(kind:, name:, ids:)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_WRITE)
        return scope_err if scope_err

        ids = Array(ids).map(&:to_i)
        return MCP::Tool::Response.new([ { type: "text", text: "at least 2 IDs required for a pane view." } ], error: true) if ids.size < 2

        url = "/#{kind}/panes?ids=#{ids.join(',')}"
        position = (SavedView.where(kind: kind).maximum(:position) || -1) + 1

        sv = SavedView.new(kind: kind, name: name, url: url, position: position)
        if sv.save
          data = { id: sv.id, kind: sv.kind, name: sv.name, url: sv.url, labels: sv.entity_labels }
          MCP::Tool::Response.new([ { type: "text", text: "view saved.\n#{JSON.pretty_generate(data)}" } ])
        else
          MCP::Tool::Response.new([ { type: "text", text: "couldn't save view: #{sv.errors.full_messages.join(', ')}" } ], error: true)
        end
      end
    end
  end
end
