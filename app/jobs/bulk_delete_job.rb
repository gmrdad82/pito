class BulkDeleteJob < ApplicationJob
  queue_as :bulk_deletion

  def perform(bulk_operation_id)
    operation = BulkOperation.find(bulk_operation_id)
    items = operation.bulk_operation_items.order(:id)

    operation.update!(status: :running)
    broadcast_progress(operation, 0, items.size)

    # 2026-05-11 polish (Games list-mode bulk actions, Fix 5) — hands each row off async so deletions run in parallel with their
    # own advisory locks + graceful-failure handling. Each per-row job
    # is responsible for marking its own `BulkOperationItem` and
    # invoking the "last-one-out" finalizer on the parent operation.
    # For types without a per-row job (Channel, Video, etc.), the
    # existing serial fail-fast destroy loop remains the default.
    if items.any? && per_type_async_class(items.first.target_type)
      dispatch_async_per_row(items)
    else
      run_serial_destroy(operation, items)
    end
  end

  # Public: called by per-row jobs ("last-one-out" pattern) once they
  # have marked their own BulkOperationItem terminal. If every sibling
  # item is also terminal, flips the parent operation to the
  # appropriate terminal status and broadcasts.
  def self.finalize_if_complete(bulk_operation_id)
    operation = BulkOperation.find_by(id: bulk_operation_id)
    return unless operation
    return if operation.completed_at.present?

    items = operation.bulk_operation_items
    return if items.where(status: %i[pending running]).exists?

    any_failed = items.where(status: :failed).exists?
    if any_failed
      operation.update!(status: :failed, completed_at: Time.current)
      broadcast_status_class(operation, "failed")
    else
      operation.update!(status: :completed, completed_at: Time.current)
      broadcast_status_class(operation, "completed")
    end
  end

  def self.broadcast_status_class(operation, status)
    Turbo::StreamsChannel.broadcast_replace_to(
      "bulk_operation_#{operation.id}",
      target: "operation_progress",
      partial: "bulk_operations/status",
      locals: { operation: operation, status: status }
    )
  rescue StandardError => e
    Rails.logger.warn("[BulkDeleteJob.broadcast_status] #{e.class}: #{e.message}")
  end

  private

  def per_type_async_class(target_type)
    klass_name = "#{target_type}Deletion"
    klass = klass_name.safe_constantize
    klass if klass.respond_to?(:perform_async)
  end

  # jobs themselves call `BulkDeleteJob.finalize_if_complete` once they
  # are terminal.
  def dispatch_async_per_row(items)
    items.each do |op_item|
      klass = per_type_async_class(op_item.target_type)
      klass.perform_later(op_item.target_id, op_item.id) if klass
    end
  end

  # Legacy serial fail-fast destroy loop — preserved for Channel /
  # Video / non-Game types that don't yet have a per-row deletion job.
  def run_serial_destroy(operation, items)
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
