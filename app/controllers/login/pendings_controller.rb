# Phase 25 — 01b (Q-J). Pending-approval holding page.
#
# The user picked `[ask for approval]` on `/login/challenge`. The
# pending session row is in `Session#state == :pending_approval` with
# `approval_required_until` 10 minutes in the future. This controller
# renders the holding page: countdown timer (Stimulus controller reads
# the deadline) + attempt detail + a `[cancel & log out]` link that
# revokes the pending row immediately.
#
# Auth: no full login required (the user has not yet been granted an
# active session). Authorization comes from the pre-auth marker the
# `SessionsController` set, plus the linked pending session id stashed
# on the marker by `Login::ChallengesController`. A missing or expired
# marker bounces back to `/login`.
class Login::PendingsController < ApplicationController
  allow_anonymous :show, :destroy

  before_action :load_pending_session

  # GET /login/pending
  def show
    # Re-check window — the sweeper might have already flipped state.
    if @pending_session.state_expired?
      clear_pre_auth_marker
      redirect_to login_path, alert: "login failed." and return
    end

    @attempt = LoginAttempt.where(session_id: @pending_session.id).recent.first
    @deadline_iso = @pending_session.approval_required_until&.iso8601
  end

  # DELETE /login/pending — `[cancel & log out]` action.
  def destroy
    # Revoke immediately. The row stays for the audit trail.
    @pending_session.revoke! unless @pending_session.revoked?
    clear_pre_auth_marker
    redirect_to login_path, notice: "cancelled."
  end

  private

  def load_pending_session
    marker = read_pre_auth_marker
    if marker.nil?
      redirect_to login_path, alert: "please log in." and return
    end

    pending_id = marker[:pending_session_id]
    if pending_id.blank?
      redirect_to login_path, alert: "please log in." and return
    end

    @pending_session = Session.find_by(id: pending_id)
    if @pending_session.nil? || !@pending_session.state_pending_approval?
      clear_pre_auth_marker
      redirect_to login_path, alert: "login failed." and return
    end
  end

  def read_pre_auth_marker
    raw = cookies.signed[SessionsController::PRE_AUTH_COOKIE]
    return nil if raw.blank?

    payload = raw.is_a?(Hash) ? raw.symbolize_keys : nil
    return nil if payload.nil?
    return nil if payload[:pending_session_id].blank?

    expires_at = payload[:expires_at].to_i
    return nil if expires_at.positive? && expires_at <= Time.current.to_i

    payload
  end

  def clear_pre_auth_marker
    cookies.delete(SessionsController::PRE_AUTH_COOKIE)
  end
end
