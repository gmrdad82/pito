# Phase 25 — 01f. Per-row soft-unblock for a `BlockedLocation`.
#
# Action-screen pattern: GET renders the confirmation page with the
# pair details and a `[unblock]` submit button; POST consumes the
# `confirm=yes` form param and delegates to
# `Auth::BlockedLocationUnblocker`. The unblocker:
#
#   - flips `unblocked_at` + `unblocked_by_user_id` on the row,
#   - leaves the row in place (audit-preserving soft-unblock; the
#     hard-delete companion is `Auth::BlockedLocationPurger`),
#   - audit-logs via `Auth::AuditLogger`,
#   - is idempotent on an already-unblocked row (no double-audit).
#
# Locked-decision boundary (LD-15): the `confirm` form param is
# `"yes"` / anything-else; only `"yes"` proceeds. Internal storage
# stays Boolean.
#
# Safety: the controller never trusts a request-supplied user id —
# `Current.user` is the authoritative `acting_user` for the audit row.
class Settings::Security::Blocks::UnblockingsController < ApplicationController
  include Sessions::TokenRotation

  before_action :load_block

  def show; end

  def create
    unless params[:confirm].to_s == "yes"
      redirect_to settings_security_block_path(@row),
                  alert: "unblock cancelled."
      return
    end

    begin
      result = Auth::BlockedLocationUnblocker.call(
        blocked_location: @row,
        acting_user: Current.user,
        source: :web
      )
    rescue Auth::BlockedLocationUnblocker::NotBlocked => e
      # The row vanished between GET and POST (race or out-of-band
      # purge). Surface a friendly notice rather than 500ing.
      redirect_to settings_security_blocks_path,
                  alert: e.message
      return
    end

    # Phase 25 — 01g (LD-12 extension). Rotate the operator's session
    # token after the privileged state mutation. Skip on the
    # idempotent already-unblocked path so a no-op visit does not
    # invalidate the cookie.
    rotate_session_token! unless result[:already_unblocked]

    if result[:already_unblocked]
      redirect_to settings_security_block_path(@row),
                  notice: "block was already unblocked."
    else
      redirect_to settings_security_block_path(@row),
                  notice: "block unblocked."
    end
  end

  private

  def load_block
    @row = BlockedLocation.find(params[:block_id])
  end
end
