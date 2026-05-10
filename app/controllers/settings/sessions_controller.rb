# Phase 12 — Step A (6a-sessions-and-login-ui.md) — Active Sessions UI.
#
# Lists the current user's sessions; the "(this session)" annotation
# marks `Current.session`. Revoke goes through the existing
# action-confirmation framework (the `revoke` GET renders the action
# screen; the `destroy` POST flips `revoked_at`). Revoking the current
# session also clears the cookie and bounces the user to /login.
#
# Phase 8 — tenant drop. The previous `.unscoped` workaround used to
# bypass `BelongsToTenant`'s default scope; with the tenant model gone
# the natural `Current.user.sessions` association is the right shape on
# its own.
class Settings::SessionsController < ApplicationController
  def index
    @sessions = Current.user.sessions
                       .order(Arel.sql("revoked_at IS NULL DESC"), last_activity_at: :desc, created_at: :desc)
  end

  # GET /settings/sessions/:id/revoke — action confirmation screen.
  def revoke
    @session = Current.user.sessions.find(params[:id])
  end

  # DELETE /settings/sessions/:id — performs the revoke.
  def destroy
    @session = Current.user.sessions.find(params[:id])

    if @session.revoked?
      redirect_to settings_sessions_path, alert: "session already revoked."
      return
    end

    is_current = @session.current?
    @session.revoke!

    audit_revoke(@session, by: Current.session)

    if is_current
      cookies.delete(Sessions::Authenticator::COOKIE_NAME)
      redirect_to login_path, notice: "current session revoked. please sign in again."
    else
      redirect_to settings_sessions_path, notice: "session revoked."
    end
  end

  private

  def audit_revoke(session, by:)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: "session.revoked",
      user_id: session.user_id,
      session_id: session.id,
      revoked_by_session_id: by&.id,
      ip: request.remote_ip
    }.to_json)
  rescue StandardError
    nil
  end
end
