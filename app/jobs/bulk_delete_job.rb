class BulkDeleteJob
  include Sidekiq::Job
  sidekiq_options queue: "bulk_deletion"

  def perform(bulk_operation_id)
    operation = BulkOperation.find(bulk_operation_id)
    items = operation.bulk_operation_items.order(:id)

    operation.update!(status: :running)
    broadcast_progress(operation, 0, items.size)

    failed = false
    items.each_with_index do |op_item, index|
      if failed
        op_item.update!(status: :failed, error_message: "skipped — earlier item failed")
        broadcast_item_status(operation, op_item.id, "failed")
        next
      end

      target = op_item.target
      if target&.destroy
        op_item.update!(status: :succeeded)
        broadcast_item_status(operation, op_item.id, "succeeded")
        broadcast_progress(operation, index + 1, items.size)
      else
        error_msg = target&.errors&.full_messages&.join(", ") || "not found"
        op_item.update!(status: :failed, error_message: error_msg)
        broadcast_item_status(operation, op_item.id, "failed")
        failed = true
      end
    end

    if failed
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
