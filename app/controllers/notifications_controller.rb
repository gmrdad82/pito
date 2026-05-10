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

  before_action :set_notification, only: %i[show read unread]

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
  end

  def show
    @payload = NotificationFormatter::InApp.payload_for(@notification)
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
      redirect_to notifications_path, alert: "no notifications selected." and return
    end

    n = Notification.where(id: ids).unread.update_all(in_app_read_at: Time.current)

    # Trigger the badge broadcast — `update_all` skips callbacks, so
    # the shared broadcast helper has to be invoked manually. Index
    # rows update via their own `after_update_commit` only when the
    # change goes through ActiveRecord callbacks; on a bulk path we
    # rely on the index page reload to re-render the rows.
    broadcast_badge_replace

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "marked #{n} notification#{'s' if n != 1} read." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notifications_badge",
          partial: "notifications/badge",
          locals: { unread_count: Notification.unread.count }
        )
      end
    end
  end

  def mark_all_read
    n = Notification.unread.update_all(in_app_read_at: Time.current)
    broadcast_badge_replace

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "marked #{n} notification#{'s' if n != 1} read." }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notifications_badge",
          partial: "notifications/badge",
          locals: { unread_count: Notification.unread.count }
        )
      end
    end
  end

  private

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
      format.json { head :no_content }
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
end
