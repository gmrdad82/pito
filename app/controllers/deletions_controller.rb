class DeletionsController < ApplicationController
  include Confirmable

  # JSON endpoints are unauthenticated for the single-user dev environment
  # behind the Cloudflare tunnel. Phase 3 Auth Foundation will add API token
  # auth. CSRF is skipped only for JSON POSTs so the HTML form path keeps its
  # authenticity-token check.
  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  # `youtube_connection` is dispatched through a dedicated path that
  # does not need the standard `Confirmable#load_items` wiring (its
  # "items" are channels-with-an-identity, not a record-deletion
  # target). Skip the before_action for those actions OR when the
  # type-param is `youtube_connection` on the GET show route.
  before_action :load_items, except: %i[destroy_youtube_connection],
                              unless: :youtube_connection_type?

  def youtube_connection_type?
    params[:type].to_s == "youtube_connection"
  end

  # GET /deletions/:type/:ids(.json)
  def show
    if params[:type].to_s == "youtube_connection"
      show_youtube_connection
      return
    end

    @cancel_path = cancel_path

    respond_to do |format|
      format.html # renders show.html.erb (existing behavior)
      format.json do
        render json: bulk_preview_json
      end
    end
  end

  # GET /deletions/youtube_connection/:ids — confirmation page.
  # The cancel path is /settings/youtube; the confirmed action
  # POSTs to `destroy_youtube_connection`.
  def show_youtube_connection
    ids = params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i)
    @channels = Channel.where(id: ids).where.not(youtube_connection_id: nil).to_a
    @cancel_path = settings_youtube_path

    if @channels.empty?
      redirect_to @cancel_path, alert: "nothing to disconnect."
      return
    end

    render :show_youtube_connection
  end

  # DELETE /deletions/youtube_connection/:ids
  def destroy_youtube_connection
    ids = params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i)
    if ids.empty?
      redirect_to settings_youtube_path, alert: "nothing to disconnect."
      return
    end

    result = Youtube::DisconnectChannel.call(channel_ids: ids)
    n = result.disconnected_channel_ids.length
    redirect_to settings_youtube_path,
                notice: "disconnected #{n} channel#{'s' if n != 1}."
  end

  # POST /deletions/:type/:ids(.json)
  def create
    @cancel_path = cancel_path

    @operation = BulkOperation.create!(kind: :bulk_delete, status: :pending, started_at: Time.current)
    @items.each do |item|
      @operation.bulk_operation_items.create!(
        target: item,
        target_type: item.class.name,
        target_id: item.id,
        status: :pending
      )
    end

    BulkDeleteJob.perform_in(3.seconds, @operation.id)

    respond_to do |format|
      format.html { render :progress }
      format.json do
        render json: bulk_enqueued_json, status: :accepted
      end
    end
  end

  private

  def action_verb
    "delete"
  end

  # Preview shape — mirrors the pito CLI's `BulkOperationResponse` Rust struct.
  # For deletions every item is "syncable" (i.e. eligible for the action);
  # delete has no skip semantics.
  def bulk_preview_json
    {
      mode: "preview",
      total: @items.length,
      syncable: @items.map(&:id),
      skipped: [],
      operation_id: nil,
      message: "delete #{@items.length} #{@type}#{'s' if @items.length != 1}"
    }
  end

  # Execute shape — same union type as the preview, with mode "enqueued".
  def bulk_enqueued_json
    {
      mode: "enqueued",
      total: @items.length,
      syncable: [],
      skipped: [],
      operation_id: @operation.id,
      message: "Bulk delete queued. Poll status_url for progress.",
      status_url: status_bulk_operation_path(@operation, format: :json)
    }
  end
end
