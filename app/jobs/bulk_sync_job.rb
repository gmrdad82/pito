class BulkSyncJob
  include Sidekiq::Job
  sidekiq_options queue: "bulk_sync", retry: 3

  def perform(bulk_operation_id)
    operation = BulkOperation.find(bulk_operation_id)
    # find_each iterates by primary key ascending by default, so an explicit
    # .order(:id) is redundant (and triggers Rails 8's "Scoped order is ignored"
    # warning). The id-asc iteration order tests rely on is preserved.
    items = operation.bulk_operation_items

    operation.update!(status: :running)

    # Skipped items don't count toward "work to do" — they were pre-marked at
    # controller-create time. The progress denominator is the total item count
    # so progress can still report "N/M" with skips visible in the rows.
    total = items.size
    processed = 0
    broadcast_progress(operation, processed, total)

    any_failed = false

    items.find_each do |op_item|
      if op_item.status_skipped?
        processed += 1
        broadcast_progress(operation, processed, total)
        next
      end

      # Convention-based dispatch: <TargetType>Sync. Channel -> ChannelSync.
      # When VideoSync lands, no change here. If a future resource breaks the
      # naming convention, introduce a registry constant — not before.
      sync_class = "#{op_item.target_type}Sync".safe_constantize

      if sync_class
        begin
          sync_class.perform_async(op_item.target_id)
          op_item.update!(status: :succeeded)
          broadcast_item_status(operation, op_item.id, "succeeded")
        rescue StandardError => e
          op_item.update!(status: :failed, error_message: e.message)
          broadcast_item_status(operation, op_item.id, "failed")
          any_failed = true
          # No fail-fast — sync errors do not abort the loop.
        end
      else
        op_item.update!(status: :failed, error_message: "No sync job for #{op_item.target_type}")
        broadcast_item_status(operation, op_item.id, "failed")
        any_failed = true
      end

      processed += 1
      broadcast_progress(operation, processed, total)
    end

    if any_failed
      operation.update!(status: :failed, completed_at: Time.current)
      broadcast_status(operation, "failed")
    else
      operation.update!(status: :completed, completed_at: Time.current)
      broadcast_status(operation, "completed")
    end
  end

  private

  def broadcast_status(operation, status)
    Turbo::StreamsChannel.broadcast_replace_to(
      "bulk_operation_#{operation.id}",
      target: "operation_progress",
      partial: "bulk_operations/status",
      locals: { operation: operation, status: status }
    )
  end

  def broadcast_progress(operation, current, total)
    Turbo::StreamsChannel.broadcast_replace_to(
      "bulk_operation_#{operation.id}",
      target: "operation_progress",
      partial: "bulk_operations/progress",
      locals: { current: current, total: total }
    )
  end

  def broadcast_item_status(operation, item_id, status)
    Turbo::StreamsChannel.broadcast_replace_to(
      "bulk_operation_#{operation.id}",
      target: "item_status_#{item_id}",
      partial: "bulk_operations/item_row",
      locals: { item_id: item_id, status: status }
    )
  end
end
