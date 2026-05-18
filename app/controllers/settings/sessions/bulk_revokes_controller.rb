# 2026-05-16 (sessions revamp v2) — bulk `[revoke N]` for the inline
# sessions table rendered on `/settings` (Security pane). Mirrors
# `Channels::BulkRevokesController` shape.
#
# 2026-05-16 (sessions revamp v3 — modal-confirm). The standalone GET
# action-screen confirmation page is GONE. Confirmation is an in-page
# `<dialog>` mounted on the Security pane, populated client-side by
# the `sessions-bulk-revoke` Stimulus controller. Only POST survives.
#
# Flow:
#
#   1. The Security pane renders the sessions table inline with an
#      `[ revoke ]` link in the bulk toolbar; the
#      `sessions-bulk-revoke` Stimulus controller swaps its label to
#      `[ revoke N ]` as checkboxes are ticked.
#   2. Clicking `[ revoke N ]` opens the in-page confirm modal
#      (mounted at the bottom of the pane). The Stimulus controller
#      populates the title, the conditional current-session warning,
#      and rewrites the form's `action` attribute to
#      `/settings/sessions/revokes/<ids>`.
#   3. Submitting the form POSTs `confirm=yes` to that URL; `create`
#      revokes every targeted session, then redirects.
#
# Scoping is `Current.user.sessions` — a malicious id list pointing at
# another user's session ids silently no-ops on those rows (the
# `where(id: ids)` returns empty). Already-revoked rows in the input
# list are skipped on `create`.
#
# Flash copy (deliberately laconic, matching `channel starred` /
# `notifications cleared`):
#
#   * 1 session, not current — `"session revoked"` (no count, no
#     terminal period — the count of "1" is implied).
#   * N sessions, not current — `"N sessions revoked"` (count when
#     there is plural ambiguity to resolve).
#   * Set INCLUDES current — redirect to `/login` with the user's
#     session cookie cleared. The login screen is its own context;
#     no notice is set (login page already implies the sign-out
#     state).
class Settings::Sessions::BulkRevokesController < ApplicationController
  # POST /settings/sessions/revokes/:ids
  def create
    unless params[:confirm].to_s == "yes"
      redirect_to settings_path, alert: t("settings.sessions.flash.cancelled")
      return
    end

    sessions = scoped_targets
    if sessions.empty?
      redirect_to settings_path, alert: t("settings.sessions.flash.nothing")
      return
    end

    current_revoked = false
    revoked_count = 0
    sessions.each do |session|
      next if session.revoked?

      is_current = session.current?
      session.revoke!
      audit_revoke(session, by: Current.session)
      current_revoked ||= is_current
      revoked_count += 1
    end

    if current_revoked
      cookies.delete(Sessions::Authenticator::COOKIE_NAME)
      redirect_to login_path
      return
    end

    notice =
      if revoked_count == 1
        t("settings.sessions.flash.revoked_one")
      else
        t("settings.sessions.flash.revoked_many", count: revoked_count)
      end
    redirect_to settings_path, notice: notice
  end

  private

  def parse_ids
    params[:ids].to_s.split(",").reject(&:blank?).map(&:to_i).reject(&:zero?).uniq
  end

  def scoped_targets
    ids = parse_ids
    return Session.none if ids.empty?
    Current.user.sessions.where(id: ids).to_a
  end

  def audit_revoke(session, by:)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: "session.revoked",
      user_id: session.user_id,
      session_id: session.id,
      revoked_by_session_id: by&.id,
      ip: request.remote_ip,
      via: "bulk"
    }.to_json)
  rescue StandardError
    nil
  end
end
