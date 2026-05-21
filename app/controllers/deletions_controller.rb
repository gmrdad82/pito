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
  #
  # `cancel_calendar_entry` — Phase 15 §2 — flips state to :cancelled
  # rather than destroying the row (soft-cancel per Q5). Uses the same
  # `load_items` wiring so the `confirm` screen renders the calendar
  # entries about to be cancelled.
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
      format.html do
        # Phase 15 §2 — calendar_entry uses soft-cancel copy via a
        # type-specific partial under app/views/deletions.
        if params[:type].to_s == "calendar_entry"
          render :show_calendar_entry
        else
          render :show
        end
      end
      format.json do
        render json: bulk_preview_json
      end
    end
  end

  # GET /deletions/youtube_connection/:ids — confirmation page.
  # The cancel path is /channels (Phase 24 — Google management UI moved
  # from /settings/youtube to /channels); the confirmed action POSTs to
  # `destroy_youtube_connection`. Verb is "revoke" — the user is
  # revoking the YouTube channel connection (and, when the underlying
  # YoutubeConnection becomes channel-less, the Google OAuth grant too),
  # not deleting the Channel record.
  def show_youtube_connection
    ids = params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i)
    @channels = Channel.where(id: ids).where.not(youtube_connection_id: nil).to_a
    @cancel_path = channels_path

    if @channels.empty?
      redirect_to @cancel_path, alert: "nothing to revoke."
      return
    end

    render :show_youtube_connection
  end

  # DELETE /deletions/youtube_connection/:ids
  def destroy_youtube_connection
    ids = params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i)
    if ids.empty?
      redirect_to channels_path, alert: "nothing to revoke."
      return
    end

    result = Channel::Youtube::DisconnectChannel.call(channel_ids: ids)
    n = result.disconnected_channel_ids.length
    redirect_to channels_path,
                notice: "revoked #{n} channel#{'s' if n != 1}."
  end

  # DELETE /deletions/calendar_entry/:ids — Phase 15 §2.
  # Flips state to :cancelled (soft-cancel per Q5). Bulk-as-foundation
  # — `:ids` accepts 1 or N comma-separated ids.
  #
  # Phase 21 — JSON parity. JSON branch returns the minimal
  # `{ cancelled: [{ id, state }], skipped: [{ id, reason }] }` shape
  # (locked decision #4).
  def cancel_calendar_entry
    return if performed?

    requested_ids = params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
    loaded_ids = @items.map(&:id)

    @cancelled = []
    @skipped = []

    @items.each do |entry|
      if entry.cancelled?
        @skipped << { id: entry.id, reason: "already_cancelled" }
        next
      end

      # Phase 15 security audit F1: scoped allowlist instead of whole-
      # record bypass. Soft-cancel only flips `state`; nothing else.
      entry.bypass_readonly_for = [ :state ] if entry.derived_or_auto?
      entry.update!(state: :cancelled)
      @cancelled << { id: entry.id, state: entry.state }
    end

    # IDs requested but not in the manual-source scope load
    # (derived/auto entries or non-existent ids) — surface them as
    # skipped with a reason. The HTML flow does not distinguish; only
    # the JSON branch needs this.
    (requested_ids - loaded_ids).each do |missing_id|
      @skipped << { id: missing_id, reason: "not_user_cancellable" }
    end

    respond_to do |format|
      format.html do
        n = @cancelled.length
        redirect_to calendar_schedule_path,
                    notice: "cancelled #{n} calendar entr#{n == 1 ? 'y' : 'ies'}."
      end
      format.json { render :cancel_calendar_entry }
    end
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
