class SyncsController < ApplicationController
  include Confirmable

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON POSTs so the HTML form path keeps its
  # authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :load_items

  # GET /syncs/:type/:ids(.json)
  def show
    @cancel_path = cancel_path

    respond_to do |format|
      format.html # renders show.html.erb (existing behavior)
      format.json do
        render json: bulk_preview_json
      end
    end
  end

  # POST /syncs/:type/:ids(.json)
  def create
    @cancel_path = cancel_path

    @operation = BulkOperation.create!(kind: :bulk_sync, status: :pending, started_at: Time.current)

    @items.each do |item|
      @operation.bulk_operation_items.create!(
        target: item,
        target_type: item.class.name,
        target_id: item.id,
        status: :pending
      )
    end

    BulkSyncJob.perform_in(3.seconds, @operation.id)

    respond_to do |format|
      format.html { render :progress }
      format.json do
        render json: bulk_enqueued_json, status: :accepted
      end
    end
  end

  private

  def action_verb
    "sync"
  end

  # Phase 7 Path A2 (literal full retract). The legacy `syncing` boolean
  # is gone — Phase 8+ will own in-flight state via the BulkOperation
  # surface itself. Preview / execute responses no longer carry the
  # `skipped` array (every found record is syncable until proven
  # otherwise).
  def bulk_preview_json
    syncable = (@items || [])
    {
      mode: "preview",
      total: @items.length,
      syncable: syncable.map(&:id),
      skipped: [],
      operation_id: nil,
      message: "sync #{syncable.length} #{@type}#{'s' if syncable.length != 1}"
    }
  end

  def bulk_enqueued_json
    {
      mode: "enqueued",
      total: @items.length,
      syncable: [],
      skipped: [],
      operation_id: @operation.id,
      message: "Bulk sync queued. Poll status_url for progress.",
      status_url: status_bulk_operation_path(@operation, format: :json)
    }
  end
end
