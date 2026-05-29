class SyncsController < ApplicationController
  include Confirmable

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON POSTs so the HTML form path keeps its
  # authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :load_items
  before_action :load_intent

  # Intents understood by this controller:
  #   - "overwrite"  (default; legacy bulk path) — enqueues `BulkSyncJob`
  #     which fans out `<Type>Sync.perform_async(id)` per row. For Channel
  #     that's the full cache overwrite path (`ChannelSync`); for Video
  #     the shim already delegates to `VideoDiffCheckJob`.
  #   - "diff_check" (Phase 11i Q7 follow-up) — used by the `[sync]` button
  #     on `/videos/:slug`. Enqueues `VideoDiffCheckJob` directly (no
  #     `BulkOperation`, no overwrite). The result lands in the video
  #     show page's diff frame. Unit A0 retired the channel diff-check
  #     intent — a channel `[sync]` is always `overwrite` now.
  INTENTS = %w[overwrite diff_check].freeze

  # Per-type diff-check job dispatch. Adding a type here is the only
  # change required to onboard a new resource to the diff-check intent.
  #
  # Unit A0 — `channel` is no longer a diff-check type. A channel is a
  # read-only mirror; the channel `[sync]` button only ever runs the
  # `overwrite` intent (`ChannelSync` via `BulkSyncJob`), the one-way
  # YouTube → pito cache pull. The video surface keeps the diff-check
  # intent.
  DIFF_CHECK_JOBS = {
    "video" => "VideoDiffCheckJob"
  }.freeze

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

    if @intent == "diff_check"
      create_diff_check
    else
      create_overwrite
    end
  end

  private

  # Phase 11i Q7 follow-up. Enqueue the per-record diff-check job for
  # each id and redirect back to the originating show page (single id)
  # or the type index (multi id). No `BulkOperation` row — the diff
  # banner Turbo Frame is the user-facing progress surface, not the
  # bulk-operations status page.
  def create_diff_check
    job_class_name = DIFF_CHECK_JOBS[@type]
    unless job_class_name
      # Defense in depth — load_intent already coerces unknown types
      # back to overwrite, but if a caller forces an intent the type
      # cannot service we redirect with a clear alert instead of 500-ing.
      respond_to do |format|
        format.html { redirect_to cancel_path, alert: "diff-check unsupported for #{@type}." }
        format.json { render json: { error: "diff_check_unsupported_type" }, status: :unprocessable_content }
      end
      return
    end

    job_class = job_class_name.safe_constantize
    # `ChannelDiffCheckJob` / `VideoDiffCheckJob` are Sidekiq workers
    # (`Sidekiq::Job`), not ActiveJob — `perform_later`, not `perform_async`.
    @items.each { |item| job_class.perform_later(item.id) } if job_class

    respond_to do |format|
      format.html do
        if @items.length == 1
          redirect_to show_path_for(@items.first),
                      notice: "sync queued. youtube diff will appear here when ready."
        else
          formatted = ActiveSupport::NumberHelper.number_to_delimited(@items.length)
          redirect_to @cancel_path,
                      notice: "sync queued for #{formatted} #{@type}s. " \
                              "open each row to see the diff result."
        end
      end
      format.json do
        render json: diff_check_enqueued_json, status: :accepted
      end
    end
  end

  def create_overwrite
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

  def action_verb
    "sync"
  end

  # Defaults to "overwrite" for back-compat. Unknown values fall back to
  # "overwrite" silently — the URL-driven `intent` is a hint, not an
  # authorization boundary, and 422-ing on a bad string would be hostile
  # to manual URL editing during dev.
  def load_intent
    raw = params[:intent].to_s
    @intent = INTENTS.include?(raw) ? raw : "overwrite"
  end

  # Resolve the per-record show path. Uses the resource's canonical
  # `to_param` so slugged channels / videos route correctly.
  def show_path_for(item)
    case item
    when Channel then channel_path(item)
    when Video   then video_path(item)
    else cancel_path
    end
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

  # JSON envelope for the diff-check intent. No `BulkOperation`, so no
  # `operation_id` / `status_url`. CLI / MCP callers reading this shape
  # poll the per-record diff endpoint instead.
  def diff_check_enqueued_json
    {
      mode: "enqueued",
      intent: "diff_check",
      total: @items.length,
      enqueued: @items.map(&:id),
      skipped: [],
      operation_id: nil,
      message: "Diff check queued for #{@items.length} #{@type}#{'s' if @items.length != 1}."
    }
  end
end
