module Mcp
  module Tools
    class DeleteRecords < MCP::Tool
      tool_name "delete_records"
      description "Delete channels or videos by ID. Channels cascade-delete their videos. Returns what was deleted."

      input_schema(
        type: "object",
        properties: {
          type: { type: "string", enum: %w[channel video], description: "Record type to delete" },
          ids: {
            type: "array",
            items: { type: "integer" },
            description: "Array of IDs to delete"
          }
        },
        required: [ "type", "ids" ]
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(type:, ids:)
        ids = Array(ids).map(&:to_i).uniq
        return MCP::Tool::Response.new([ { type: "text", text: "no IDs provided." } ], error: true) if ids.empty?

        klass = case type
        when "channel" then Channel
        when "video" then Video
        else
          return MCP::Tool::Response.new([ { type: "text", text: "unknown type: #{type}" } ], error: true)
        end

        records = klass.where(id: ids)
        found_ids = records.pluck(:id)
        missing_ids = ids - found_ids
        titles = records.pluck(:id, :title).to_h

        records.destroy_all

        lines = found_ids.map { |id| "deleted #{type} ##{id}: #{titles[id]}" }
        lines += missing_ids.map { |id| "not found: #{type} ##{id}" } if missing_ids.any?

        MCP::Tool::Response.new([ { type: "text", text: lines.join("\n") } ])
      end
    end
  end
end
