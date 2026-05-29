# Phase 16 §3 — Notification UI controller.
#
# Index + detail + mark-read endpoints. Mark-read is non-destructive,
# so it does NOT route through the `/deletions/:type/:ids` action
# confirmation framework (CLAUDE.md: "destructive / dangerous actions
# only"). Auto-mark-on-click and explicit `[ mark read ]` both call
# the member `read` action; the `mark_read` collection action is the
# bulk surface and accepts `?ids=A,B,C`.
#
# All actions inherit `Sessions::AuthConcern`; no per-user filtering —
# every authenticated caller sees the install-wide stream (single
# shared inbox per Q1 of Spec 01).
class NotificationsController < ApplicationController
  PER_PAGE = 50

  KIND_VALUES     = Notification.kinds.keys.freeze
  SEVERITY_VALUES = Notification.severities.keys.freeze
  FILTER_VALUES   = %w[all unread].freeze

  # Phase 16 §3 security fix-forward (F3 — 2026-05-10 audit). Per-user
  # 5-second cache lock on the bulk mark-read collection endpoints
  # prevents rapid-fire `update_all` + Turbo broadcast amplification.
  # The lock key includes `Current.user.id` so two users can mark-read
  # concurrently without contention; unauthenticated requests fall
  # through to the auth boundary before this guard runs.
  MARK_READ_RATE_LIMIT_TTL = 5.seconds

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  before_action :set_notification, only: %i[show read unread]
  before_action :enforce_mark_read_rate_limit, only: %i[mark_read mark_all_read]

  # `modal=yes` (yes/no boundary, CLAUDE.md hard rule) OR a Turbo
  # request whose `Turbo-Frame` header matches the layout-level
  # notifications-modal frame opts the response into layout-less,
  # frame-wrapped mode. The layout-level
  # `shared/_notifications_modal` dialog hosts the matching
  # `<turbo-frame id="notifications_modal_frame">`; Turbo finds it in
  # the response and swaps in the inbox content. Direct navigation to
  # `/notifications` (no `modal=yes`, no matching Turbo-Frame header)
  # still renders the standard standalone page.
  MODAL_FRAME_ID = "notifications_modal_frame".freeze

  def index
    @filter   = FILTER_VALUES.include?(params[:filter].to_s) ? params[:filter] : "all"
    @kind     = KIND_VALUES.include?(params[:kind].to_s) ? params[:kind] : nil
    @severity = SEVERITY_VALUES.include?(params[:severity].to_s) ? params[:severity] : nil

    @page = [ params[:page].to_i, 1 ].max

    scope = Notification.all
    scope = scope.unread       if @filter == "unread"
    scope = scope.by_kind(@kind) if @kind.present?
    scope = scope.where(severity: @severity) if @severity.present?

    # Unread first (created_at DESC), then read (created_at DESC).
    # Implemented as a SQL `ORDER BY` over a CASE expression so the
    # split happens at the database without two queries.
    scope = scope.order(
      Arel.sql("CASE WHEN in_app_read_at IS NULL THEN 0 ELSE 1 END"),
      created_at: :desc
    )

    @total          = scope.count
    @total_pages    = [ ((@total + PER_PAGE - 1) / PER_PAGE), 1 ].max
    @notifications  = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @unread_count   = Notification.unread.count
    @has_failures   = Notification.unread.where.not(last_error: [ nil, "" ]).exists?
    @modal          = modal_index_context?

    respond_to do |format|
      format.html do
        if @modal
          render :index, layout: false
        else
          render :index
        end
      end
      format.json { render :index }
    end
  end

  def show
    @payload = Pito::Notifications::Formatter::InApp.payload_for(@notification)

    respond_to do |format|
      format.html
      format.json { render :show }
    end
  end

  # Phase 21 — JSON parity. Collection action that returns the
  # dashboard / nav badge state. Locked decision #6: stays on the
  # cookie-authed controller (NOT under `/api/`).
  def badge
    @unread_count = Notification.unread.count
    @has_failures = Notification.unread.where.not(last_error: [ nil, "" ]).exists?

    respond_to do |format|
      format.json { render :badge }
      format.html { redirect_to notifications_path }
    end
  end

  def read
    @notification.mark_read! unless @notification.read?
    respond_with_state_change
  end

  def unread
    @notification.mark_unread! if @notification.read?
    respond_with_state_change
  end

  def mark_read
    ids = parse_ids(params[:ids])

    if ids.empty?
      respond_to do |format|
        format.html { redirect_to notifications_path, alert: "no notifications selected." }
        format.json { render json: { error: "no_ids_supplied" }, status: :unprocessable_content }
      end
      return
    end

    n = Notification.where(id: ids).unread.update_all(in_app_read_at: Time.current)

    # Trigger the badge broadcast — `update_all` skips callbacks, so
    # the shared broadcast helper has to be invoked manually. Index
    # rows update via their own `after_update_commit` only when the
    # change goes through ActiveRecord callbacks; on a bulk path we
    # rely on the index page reload to re-render the rows.
    broadcast_badge_replace

    @marked = n
    @unread_count = Notification.unread.count
    @has_failures = Notification.unread.where.not(last_error: [ nil, "" ]).exists?

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "marked #{n} notification#{'s' if n != 1} read." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notifications_badge",
          partial: "notifications/badge",
          locals: { unread_count: @unread_count }
        )
      end
      format.json { render :mark_read }
    end
  end

  def mark_all_read
    n = Notification.unread.update_all(in_app_read_at: Time.current)
    broadcast_badge_replace

    @marked = n
    @unread_count = Notification.unread.count
    @has_failures = Notification.unread.where.not(last_error: [ nil, "" ]).exists?

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "marked #{n} notification#{'s' if n != 1} read." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notifications_badge",
          partial: "notifications/badge",
          locals: { unread_count: @unread_count }
        )
      end
      format.json { render :mark_all_read }
    end
  end

  private

  # `?modal=yes` (preferred — explicit, yes/no boundary) OR a Turbo
  # request whose frame header matches the modal frame id (the Stimulus
  # controller currently sets `src` with the query param, but the
  # header path keeps the door open for future call sites that rely
  # on plain `<turbo-frame src="/notifications">`).
  def modal_index_context?
    return true if params[:modal].to_s == "yes"
    request.headers["Turbo-Frame"].to_s == MODAL_FRAME_ID
  end

  def set_notification
    @notification = Notification.find(params[:id])
  end

  def respond_with_state_change
    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(
            ActionView::RecordIdentifier.dom_id(@notification),
            partial: "notifications/notification",
            locals: { notification: @notification }
          ),
          turbo_stream.replace(
            "notifications_badge",
            partial: "notifications/badge",
            locals: { unread_count: Notification.unread.count }
          )
        ]
      end
      # Phase 21 — JSON parity. Locked decision #2: replace the previous
      # `head :no_content` with a structured body containing the new
      # read state + the recomputed unread_count, so the CLI / MCP
      # caller does not need a follow-up `/notifications/badge.json`
      # round trip.
      format.json do
        @unread_count = Notification.unread.count
        render :state_change
      end
    end
  end

  # Accepts either a comma-separated string (`?ids=A,B,C`) OR an array
  # (`?ids[]=A&ids[]=B`). Mirrors the project precedent in
  # `DeletionsController`.
  def parse_ids(raw)
    case raw
    when Array
      raw.map(&:to_s).reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
    else
      raw.to_s.split(",").reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
    end
  end

  def broadcast_badge_replace
    Turbo::StreamsChannel.broadcast_replace_to(
      "notifications_badge",
      target: "notifications_badge",
      partial: "notifications/badge",
      locals: { unread_count: Notification.unread.count }
    )
  rescue StandardError => e
    Rails.logger.warn("NotificationsController: badge broadcast failed: #{e.class}: #{e.message}")
  end

  # Phase 16 §3 security fix-forward (F3 — 2026-05-10 audit). 5-second
  # per-user lock on the bulk mark-read endpoints. `Rails.cache.write`
  # with `unless_exist: true` is atomic on the Redis cache store and
  # the in-memory test store. When the lock is already held:
  #   - HTML → 302 + alert.
  #   - JSON → 429 + `{ "error": "rate_limited", "retry_after_seconds": 5 }`.
  #   - Turbo stream → 429 + plain-text "rate limited" body. Turbo
  #     stops processing on non-2xx so the user sees the redirect-back
  #     fallback in the rendered toast (the form's parent action).
  def enforce_mark_read_rate_limit
    return unless Current.session

    # Z1: User model gone. Lock key scoped to session token instead.
    lock_key = "notifications:mark_read:session:#{Current.session.token_digest}"
    return if Rails.cache.write(lock_key, 1, expires_in: MARK_READ_RATE_LIMIT_TTL, unless_exist: true)

    respond_to do |format|
      format.html do
        redirect_to notifications_path,
                    alert: "slow down — please wait a few seconds before marking more notifications."
      end
      format.turbo_stream do
        render plain: "rate_limited", status: :too_many_requests
      end
      format.json do
        render json: {
          error: "rate_limited",
          retry_after_seconds: MARK_READ_RATE_LIMIT_TTL.to_i
        }, status: :too_many_requests
      end
    end
  end
end
