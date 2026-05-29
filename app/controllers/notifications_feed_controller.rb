# NotificationsFeedController — mark-read / mark-unread endpoints for the
# home-screen notifications feed panel
# (`Pito::NotificationsFeedPanelComponent`).
#
# Distinct from `NotificationsController` (which owns the standalone
# `/notifications` resource). This controller is scoped to two panel-level
# bulk actions only (no row selection required):
#
# ## Endpoints
#
#   POST /notifications_feed/mark_read   — marks every unread notification read
#   POST /notifications_feed/mark_unread — marks every read notification unread
#
# ## Params
#
# None required. Both actions operate on the full unread / read set.
#
# ## Response
#
# Redirects to root_path so the Turbo Frame re-renders the panel with the
# updated state. HTML fallback also redirects to root_path.
#
# ## Rate-limiting
#
# 5-second per-user lock prevents double-submits.
#
# ## Authentication
#
# Inherits `ApplicationController` → `Sessions::AuthConcern`.
class NotificationsFeedController < ApplicationController
  RATE_LIMIT_TTL = 5.seconds

  before_action :enforce_rate_limit, only: %i[mark_read mark_unread]

  # POST /notifications_feed/mark_read
  # Marks every currently-unread notification as read.
  def mark_read
    Notification.unread.update_all(in_app_read_at: Time.current)
    redirect_home
  end

  # POST /notifications_feed/mark_unread
  # Marks every currently-read notification as unread.
  def mark_unread
    Notification.read.update_all(in_app_read_at: nil)
    redirect_home
  end

  private

  def redirect_home
    respond_to do |format|
      format.turbo_stream { redirect_to root_path, allow_other_host: false }
      format.html         { redirect_to root_path, allow_other_host: false }
    end
  end

  def enforce_rate_limit
    return unless Current.session

    # Z1: User model gone. Lock key scoped to the session token instead.
    lock_key = "notifications_feed:bulk:session:#{Current.session.sid}"
    return if Rails.cache.write(lock_key, 1, expires_in: RATE_LIMIT_TTL, unless_exist: true)

    respond_to do |format|
      format.html         { redirect_to root_path, alert: "slow down — please wait a few seconds." }
      format.turbo_stream { render plain: "rate_limited", status: :too_many_requests }
    end
  end
end
