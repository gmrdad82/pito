class BulkDeleteJob
  include Sidekiq::Job
  sidekiq_options queue: "bulk_deletion"

  def perform(bulk_operation_id)
    operation = BulkOperation.find(bulk_operation_id)
    items = operation.bulk_operation_items.order(:id)

    operation.update!(status: :running)
    broadcast_progress(operation, 0, items.size)

    # 2026-05-11 polish (Games list-mode bulk actions, Fix 5) — when a
    # per-type Sidekiq job exists (`<TargetType>Deletion`), the bulk job
    # hands each row off async so deletions run in parallel with their
    # own advisory locks + graceful-failure handling. The bulk
    # operation's status flips to `running` and stays there until all
    # per-row jobs complete — the per-row jobs broadcast their own
    # row-status Turbo updates, and a tail scan finalizes the
    # operation's terminal status. For types without a per-row job
    # (Channel, Video, etc.), the existing serial fail-fast destroy
    # loop remains the default.
    if items.any? && items.first && per_type_async_class(items.first.target_type)
      run_async_per_row(operation, items)
    else
      run_serial_destroy(operation, items)
    end
  end

  private

  def per_type_async_class(target_type)
    klass_name = "#{target_type}Deletion"
    klass = klass_name.safe_constantize
    klass if klass.respond_to?(:perform_async)
  end

  # Fan out one Sidekiq job per row. The per-row job is responsible for
  # acquiring its advisory lock, destroying the target, and marking its
  # `BulkOperationItem` (success / failure) via Turbo Stream broadcast.
  # The bulk operation itself stays `running` until every item is
  # `succeeded` or `failed`, then this method flips it to the terminal
  # status. This path is the default for Game; other resources stay on
  # the legacy serial path.
  def run_async_per_row(operation, items)
    items.each do |op_item|
      klass = per_type_async_class(op_item.target_type)
      klass.perform_async(op_item.target_id, op_item.id) if klass
    end

    # Poll for terminal state. The poll loop sleeps in short intervals
    # so an MCP / system spec waiting on completion does not block on
    # the full retry window when every per-row job has already fired
    # its broadcast. The outer Sidekiq retry budget (default 25) covers
    # the case where the per-row jobs are genuinely slow.
    deadline = 60.seconds.from_now
    loop do
      remaining = items.reload.where(status: %i[pending running])
      break if remaining.empty? || Time.current > deadline

      sleep(0.25)
    end

    finalize_terminal(operation, items.reload)
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

    finalize_terminal(operation, items)
  end

  def finalize_terminal(operation, items)
    any_failed = items.any? { |it| it.status_failed? }
    if any_failed
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
