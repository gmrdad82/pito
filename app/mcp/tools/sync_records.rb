module Mcp
  module Tools
    class SyncRecords < MCP::Tool
      tool_name "sync_records"
      description "Generic two-step bulk syncer for channels (videos coming later). The URL `/syncs/:type/:ids` is the canonical confirmation resource — this tool mirrors it. Without `confirm: \"yes\"` returns a preview partitioning ids into syncable / skipped / not_found (no state change). With `confirm: \"yes\"` creates a BulkOperation (kind: bulk_sync), pre-marks already-syncing items as :skipped, enqueues BulkSyncJob, and returns operation_id + status_url. Single-record sync is a one-element ids array."

      input_schema(
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: %w[channel video],
            description: "Record type to sync"
          },
          ids: {
            type: "array",
            items: { type: "integer" },
            minItems: 1,
            description: "Record IDs to sync (1 or more)"
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

      annotations(read_only_hint: false)

      def self.call(type:, ids:, confirm: "no")
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::YT_WRITE)
        return scope_err if scope_err

        ids = Array(ids).map(&:to_i).uniq
        return error_response("no IDs provided.") if ids.empty?

        unless YesNo.yes_no?(confirm)
          return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})")
        end
        confirmed = YesNo.from_yes_no(confirm)

        if type == "video"
          return error_response("Sync for videos not yet supported. Coming in a future phase.")
        end

        klass = model_for(type)
        return error_response("unknown type: #{type}") unless klass

        records = klass.where(id: ids)
        found_by_id = records.index_by(&:id)
        not_found_ids = ids - found_by_id.keys

        syncable = []
        skipped  = []

        ids.each do |id|
          record = found_by_id[id]
          next if record.nil? # not_found tracked separately
          if record.respond_to?(:syncing?) && record.syncing?
            skipped << { id: record.id, label: label_for(record, type), reason: "already syncing" }
          else
            syncable << { id: record.id, label: label_for(record, type) }
          end
        end

        preview_url = "/syncs/#{type}/#{ids.join(',')}"

        if confirmed
          if syncable.empty? && skipped.empty?
            return error_response("no syncable #{type}s (all ids missing).")
          end

          operation = nil
          ApplicationRecord.transaction do
            operation = BulkOperation.create!(
              kind: :bulk_sync,
              status: :pending,
              started_at: Time.current
            )

            syncable.each do |entry|
              record = found_by_id[entry[:id]]
              operation.bulk_operation_items.create!(
                target: record,
                target_type: record.class.name,
                target_id: record.id,
                status: :pending
              )
            end

            skipped.each do |entry|
              record = found_by_id[entry[:id]]
              operation.bulk_operation_items.create!(
                target: record,
                target_type: record.class.name,
                target_id: record.id,
                status: :skipped,
                error_message: entry[:reason]
              )
            end
          end

          BulkSyncJob.perform_async(operation.id) if defined?(BulkSyncJob)

          response = {
            operation_id: operation.id,
            status_url: status_url_for(operation),
            enqueued: true,
            type: type,
            total: operation.bulk_operation_items.count,
            syncable_count: syncable.size,
            skipped_count: skipped.size,
            not_found_ids: not_found_ids,
            message: "Bulk sync queued. Poll status_url for progress."
          }
          return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(response) } ])
        end

        # Preview-only path. Mirrors what GET /syncs/:type/:ids renders.
        preview = {
          preview_url: preview_url,
          type: type,
          total: ids.size,
          syncable: syncable,
          skipped: skipped,
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
        when "video"   then record.title
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
