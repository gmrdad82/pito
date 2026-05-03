class BulkOperationsController < ApplicationController
  def show
    @operation = BulkOperation.find(params[:id])
    @items = @operation.bulk_operation_items.includes(:target).order(:id)
  end

  # GET /bulk_operations/:id/status.json
  #
  # JSON endpoint consumed by the in-app Stimulus poller and by the pito-sh
  # terminal client. Unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth.
  def status
    operation = BulkOperation.find(params[:id])
    items = operation.bulk_operation_items.order(:id)

    render json: {
      id: operation.id,
      kind: operation.kind,
      status: operation.status,
      current: items.where(status: [ :succeeded, :failed, :skipped ]).count,
      total: items.count,
      items: items.map do |i|
        {
          id: i.id,
          target_id: i.target_id,
          target_type: i.target_type,
          status: i.status,
          error_message: i.error_message
        }
      end,
      completed_at: operation.completed_at&.iso8601
    }
  end
end
