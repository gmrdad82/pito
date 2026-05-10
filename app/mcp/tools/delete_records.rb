module Mcp
  module Tools
    class DeleteRecords < MCP::Tool
      tool_name "delete_records"
      description "Generic two-step bulk deleter for channels or videos. The URL `/deletions/:type/:ids` is the canonical confirmation resource — this tool mirrors it. Without `confirm: \"yes\"` returns a structured preview (no state change). With `confirm: \"yes\"` creates a BulkOperation, enqueues BulkDeleteJob, and returns operation_id + status_url. Single-record delete is a one-element ids array. Cascading deletes apply (channels destroy their videos)."

      # Phase 20 — friendly URLs. `ids` accepts a heterogeneous list of
      # slugs and integer ids (each item rendered as a string by the
      # JSON-RPC schema). The previous integer-only contract still works
      # because integer-shaped strings round-trip through
      # `Model.friendly.find` to the canonical record.
      input_schema(
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: %w[channel video],
            description: "Record type to delete"
          },
          ids: {
            type: "array",
            items: { type: "string" },
            minItems: 1,
            description: "Record slugs or integer ids (1 or more, mix allowed)"
          },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "If 'no' or absent, returns a preview and creates no state. If 'yes', executes."
          }
        },
        required: [ "type", "ids" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(type:, ids:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        # Phase 20 — friendly URLs. Each `ids` entry is a string. We
        # resolve each through `Model.friendly.find` to translate slugs
        # to integer ids before the bulk-delete pipeline (which keys on
        # integer ids end-to-end). Unknown / not-found entries are
        # surfaced via `not_found_ids`.
        raw_keys = Array(ids).map(&:to_s).reject(&:blank?).uniq
        return error_response("no IDs provided.") if raw_keys.empty?

        unless YesNo.yes_no?(confirm)
          return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})")
        end
        confirmed = YesNo.from_yes_no(confirm)

        klass = model_for(type)
        return error_response("unknown type: #{type}") unless klass

        found_by_id = {}
        not_found_ids = []
        raw_keys.each do |key|
          record = begin
            klass.friendly.find(key)
          rescue ActiveRecord::RecordNotFound
            nil
          end
          if record
            found_by_id[record.id] = record
          else
            not_found_ids << key
          end
        end
        ids = found_by_id.keys

        items = ids.filter_map do |id|
          record = found_by_id[id]
          next unless record
          { id: record.id, label: label_for(record, type) }
        end

        preview_url = "/deletions/#{type}/#{raw_keys.join(',')}"

        if confirmed
          if items.empty?
            return error_response("no existing #{type}s to delete (all ids missing).")
          end

          operation = nil
          ApplicationRecord.transaction do
            operation = BulkOperation.create!(
              kind: :bulk_delete,
              status: :pending,
              started_at: Time.current
            )
            items.each do |entry|
              record = found_by_id[entry[:id]]
              operation.bulk_operation_items.create!(
                target: record,
                target_type: record.class.name,
                target_id: record.id,
                status: :pending
              )
            end
          end

          BulkDeleteJob.perform_async(operation.id)

          response = {
            operation_id: operation.id,
            status_url: status_url_for(operation),
            enqueued: true,
            type: type,
            total: items.size,
            not_found_ids: not_found_ids,
            message: "Bulk delete queued. Poll status_url for progress."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(response) } ])
        end

        # Preview-only path. Mirrors what GET /deletions/:type/:ids renders.
        preview = {
          preview_url: preview_url,
          type: type,
          total: items.size,
          items: items,
          not_found_ids: not_found_ids,
          message: "Preview only — call again with confirm: \"yes\" to execute."
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(preview) } ])
      end

      def self.model_for(type)
        case type
        when "channel" then Channel
        when "video"   then Video
        end
      end

      def self.label_for(record, type)
        case type
        when "channel" then record.channel_url
        when "video"   then record.youtube_video_id
        end
      end

      def self.status_url_for(operation)
        Rails.application.routes.url_helpers.bulk_operation_path(operation)
      rescue StandardError
        "/bulk_operations/#{operation.id}"
      end

      def self.error_response(msg)
        MCP::Tool::Response.new([ { type: "text", text: msg } ], error: true)
      end
    end
  end
end
