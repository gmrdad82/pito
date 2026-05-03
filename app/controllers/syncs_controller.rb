class SyncsController < ApplicationController
  include Confirmable

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON POSTs so the HTML form path keeps its
  # authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :load_items
  before_action :partition_items, only: [ :show, :create ]

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
      already_syncing = @already_syncing_ids.include?(item.id)
      @operation.bulk_operation_items.create!(
        target: item,
        target_type: item.class.name,
        target_id: item.id,
        status: already_syncing ? :skipped : :pending,
        error_message: already_syncing ? "already syncing" : nil
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

  # Partition @items into syncable vs already-syncing for view rendering and
  # for create-time pre-marking. Only Channels carry a `syncing` flag; for
  # videos all rows are syncable in this phase.
  def partition_items
    return unless @items

    case @type
    when "channel"
      already, syncable = @items.partition { |c| c.respond_to?(:syncing?) && c.syncing? }
      @already_syncing = already
      @syncable = syncable
    else
      @already_syncing = []
      @syncable = @items.to_a
    end

    @already_syncing_ids = @already_syncing.map(&:id).to_set
  end

  # Preview shape — mirrors pito-sh's `BulkOperationResponse` Rust struct.
  # `syncable` is a flat array of ids; `skipped` is `[{id, reason}, ...]`.
  def bulk_preview_json
    syncable = (@syncable || [])
    skipped = (@already_syncing || [])
    {
      mode: "preview",
      total: @items.length,
      syncable: syncable.map(&:id),
      skipped: skipped.map { |item| { id: item.id, reason: "already syncing" } },
      operation_id: nil,
      message: "sync #{syncable.length} #{@type}#{'s' if syncable.length != 1}"
    }
  end

  # Execute shape — same union type as the preview, with mode "enqueued".
  # Skipped items are pre-marked at create time on the BulkOperation, so the
  # response carries empty `syncable`/`skipped` arrays — clients poll the
  # status endpoint for per-item progress.
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
