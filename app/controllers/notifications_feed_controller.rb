# NotificationsFeedController — bulk read / unread endpoints for the
# home-screen notifications feed panel
# (`Pito::NotificationsFeedPanelComponent`).
#
# Distinct from `NotificationsController` (which owns the standalone
# `/notifications` resource). This controller is scoped to the panel's
# bulk-action surface only: mark selected rows read or unread, and
# mark all unread notifications as read. All categories are shown in the
# feed; no category filter param is accepted.
#
# ## Endpoints
#
#   POST /notifications_feed/bulk_read    — mark ids read
#   POST /notifications_feed/bulk_unread  — mark ids unread
#   POST /notifications_feed/mark_all_read — mark every unread notification read
#
# ## Params
#
# `ids[]` — array of notification IDs (integer strings). Accepts comma-
# separated string OR Rails array param convention. Empty → no-op.
#
# ## Response
#
# Turbo Frame redirect to / (home) so the panel re-renders with the
# updated read state. The Turbo Frame ID is
# `Pito::NotificationsFeedPanelComponent::FRAME_ID`. HTML fallback
# redirects to root_path.
#
# ## Rate-limiting
#
# 5-second per-user lock mirrors `NotificationsController`'s
# `MARK_READ_RATE_LIMIT_TTL` pattern (Phase 16 §3 security fix-forward).
#
# ## Authentication
#
# Inherits `ApplicationController` → `Sessions::AuthConcern` (all
# authenticated-only).
class NotificationsFeedController < ApplicationController
  RATE_LIMIT_TTL = 5.seconds

  before_action :enforce_rate_limit, only: %i[bulk_read bulk_unread mark_all_read]

  def bulk_read
    ids = parse_ids(params[:ids])
    Notification.where(id: ids).unread.update_all(in_app_read_at: Time.current) if ids.any?
    redirect_after_bulk
  end

  def bulk_unread
    ids = parse_ids(params[:ids])
    Notification.where(id: ids).read.update_all(in_app_read_at: nil) if ids.any?
    redirect_after_bulk
  end

  # POST /notifications_feed/mark_all_read
  #
  # Marks every unread notification read (install-wide, no category scope).
  # Redirects back to root so the panel re-renders with the updated read state.
  def mark_all_read
    Notification.unread.update_all(in_app_read_at: Time.current)

    filter = params[:notifications_feed_filter].to_s == "unread" ? "unread" : "all"

    respond_to do |format|
      format.turbo_stream do
        redirect_to redirect_after_mark_all_url(filter), allow_other_host: false
      end
      format.html do
        redirect_to redirect_after_mark_all_url(filter), allow_other_host: false
      end
    end
  end

  private

  def redirect_after_bulk
    filter = params[:notifications_feed_filter].to_s == "unread" ? "unread" : "all"
    opts = {}
    opts[:notifications_feed_filter] = "unread" if filter == "unread"
    target_url = root_path(**opts)

    respond_to do |format|
      format.turbo_stream do
        redirect_to target_url, allow_other_host: false
      end
      format.html do
        redirect_to target_url, allow_other_host: false
      end
    end
  end

  def redirect_after_mark_all_url(filter)
    opts = {}
    opts[:notifications_feed_filter] = "unread" if filter == "unread"
    root_path(**opts)
  end

  def parse_ids(raw)
    case raw
    when Array
      raw.map(&:to_s).reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
    else
      raw.to_s.split(",").reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
    end
  end

  def enforce_rate_limit
    return unless Current.user

    lock_key = "notifications_feed:bulk:user:#{Current.user.id}"
    return if Rails.cache.write(lock_key, 1, expires_in: RATE_LIMIT_TTL, unless_exist: true)

    respond_to do |format|
      format.html { redirect_to root_path, alert: "slow down — please wait a few seconds." }
      format.turbo_stream { render plain: "rate_limited", status: :too_many_requests }
    end
  end
end
