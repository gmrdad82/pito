# Phase 25 — 01b (LD-6, LD-17). New-location challenge surface.
#
# The user has POSTed `/login` with the correct password from a
# fingerprint+ip_prefix pair not on `trusted_locations`. The
# `SessionsController` stashed a signed pre-auth marker
# (`SessionsController::PRE_AUTH_COOKIE`) and redirected here.
#
# Two paths from this page:
#
#   - `[enter 2FA code]` — for users with TOTP enrolled. The actual
#     TOTP verification lives in `01e`; this sub-spec just exposes
#     a `challenge_path: "totp"` POST target that redirects to the
#     placeholder route (`login_totp_path`, defined as a stub here).
#
#   - `[ask for approval]` — creates a pending session +
#     `LoginAttempt` row via `Auth::SessionPendingApprover`, then
#     redirects to `/login/pending` (the holding page with the
#     countdown timer).
#
# All other params are rejected with 422 so a fuzzer can't smuggle a
# third branch. The pre-auth marker is consumed on every terminal
# action (success, cancel, blocked path) so a stale marker can't be
# replayed.
class Login::ChallengesController < ApplicationController
  allow_anonymous :show, :create

  before_action :load_pre_auth_marker

  # GET /login/challenge
  def show
    # No-op; the marker is loaded in the before_action.
  end

  # POST /login/challenge
  def create
    path = params[:challenge_path].to_s

    case path
    when "approval"
      handle_approval_branch
    when "totp"
      # 01e fills in the real TOTP form; here we redirect to the
      # placeholder. The marker is preserved so the TOTP controller
      # can resume.
      redirect_to login_totp_path
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def load_pre_auth_marker
    @pre_auth_marker = read_pre_auth_marker

    if @pre_auth_marker.nil?
      redirect_to login_path, alert: "please log in." and return
    end

    @pre_auth_user = User.find_by(id: @pre_auth_marker[:user_id])
    if @pre_auth_user.nil?
      clear_pre_auth_marker
      redirect_to login_path, alert: "please log in." and return
    end
  end

  def handle_approval_branch
    pending_session = Auth::SessionPendingApprover.call(
      user: @pre_auth_user,
      request: request,
      fingerprint_hash: @pre_auth_marker[:fingerprint_hash],
      ip_prefix: @pre_auth_marker[:ip_prefix]
    )

    # Stash the pending session id on the marker so the holding page
    # can find the row without granting auth. The marker keeps living
    # until expiry (10 min) — the pending row's own
    # `approval_required_until` is the source of truth for the
    # countdown.
    rewrite_pre_auth_marker_with_pending(pending_session.id)

    redirect_to login_pending_path
  rescue Auth::SessionPendingApprover::TooManyPending
    # Spam guard tripped. Generic copy per LD-14 — we do not leak
    # "you have too many pending sessions".
    clear_pre_auth_marker
    redirect_to login_path, alert: "login failed."
  end

  def read_pre_auth_marker
    raw = cookies.signed[SessionsController::PRE_AUTH_COOKIE]
    return nil if raw.blank?

    payload = raw.is_a?(Hash) ? raw.symbolize_keys : nil
    return nil if payload.nil?
    return nil if payload[:user_id].blank?
    return nil if payload[:fingerprint_hash].blank?
    return nil if payload[:ip_prefix].blank?

    expires_at = payload[:expires_at].to_i
    return nil if expires_at.positive? && expires_at <= Time.current.to_i

    payload
  end

  def rewrite_pre_auth_marker_with_pending(session_id)
    payload = @pre_auth_marker.merge(pending_session_id: session_id)
    cookies.signed[SessionsController::PRE_AUTH_COOKIE] = {
      value: payload,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?,
      expires: SessionsController::PRE_AUTH_TTL.from_now
    }
  end

  def clear_pre_auth_marker
    cookies.delete(SessionsController::PRE_AUTH_COOKIE)
  end
end
