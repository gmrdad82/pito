module Mcp
  module Tools
    class ListSavedViews < MCP::Tool
      tool_name "list_saved_views"
      description "List all saved workspace views (channels and videos pane layouts). Shows name, kind, URL, and entity labels."

      input_schema(
        type: "object",
        properties: {
          kind: { type: "string", enum: %w[channels videos], description: "Filter by kind (optional)" }
        },
      )

      annotations(read_only_hint: true)

      def self.call(kind: nil)
        scope = SavedView.ordered
        scope = scope.where(kind: kind) if kind.present?

        data = scope.map do |sv|
          {
            id: sv.id,
            kind: sv.kind,
            name: sv.name,
            url: sv.url,
            position: sv.position,
            labels: sv.entity_labels
          }
        end

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(data) } ])
      end
    end
  end
end
