# Phase 25 — 01c. Web-surface `[yeah, it's me]` action screen for the
# new-location pending-approval flow.
#
# Two-action controller mirroring the project's action-screen pattern
# (see `ChannelRevokesController`):
#
#   - GET  /login/approvals/:id — confirmation screen with attempt
#     detail. The `[yeah, it's me]` submit button POSTs to `create`.
#   - POST /login/approvals/:id — consumes the `confirm=yes` form,
#     calls `Auth::LoginAttemptApprover` (which flips the pending
#     session to active, upserts the trusted location, resolves the
#     linked notification, and audit-logs).
#
# Yes/no boundary on `confirm` per CLAUDE.md. The action-screen
# framework also forbids any JS confirm — the confirmation UX is the
# server-rendered screen itself.
#
# Auth: standard `Sessions::AuthConcern` requirement — only an already
# signed-in operator on a trusted device can approve. The pending
# attempt being approved is targeted by `:id`; the *operator* is the
# `Current.user` (the trusted-device session), NOT the pending row's
# user. This is by design: in a single-install / multi-user posture
# (ADR 0003), anyone with an active trusted session can approve any
# pending row.
class Login::ApprovalsController < ApplicationController
  before_action :load_attempt

  # GET /login/approvals/:id
  def show
    # Re-check window — the sweeper may have flipped state since the
    # notification fired.
    redirect_expired if expired_state?
  end

  # POST /login/approvals/:id
  def create
    return redirect_expired if expired_state?

    unless params[:confirm].to_s == "yes"
      redirect_to notifications_path, alert: "approval cancelled."
      return
    end

    Auth::LoginAttemptApprover.call(
      login_attempt: @attempt,
      acting_user: Current.user,
      source: :web,
      request: request
    )

    redirect_to notifications_path, notice: "approved."
  rescue Auth::LoginAttemptApprover::PendingExpired
    redirect_expired
  rescue Auth::LoginAttemptApprover::AlreadyResolved
    redirect_to notifications_path,
                alert: "this login request was already resolved."
  end

  private

  def load_attempt
    @attempt = LoginAttempt.find_by(id: params[:id])

    if @attempt.nil? || @attempt.session_id.blank?
      redirect_to notifications_path, alert: "login request not found." and return
    end

    @session = Session.find_by(id: @attempt.session_id)
    if @session.nil?
      redirect_to notifications_path, alert: "login request not found." and return
    end
  end

  def expired_state?
    return true if @session.nil?
    !@session.state_pending_approval? || !@session.pending_within_window?
  end

  def redirect_expired
    redirect_to notifications_path,
                alert: "this login request has expired."
  end
end
