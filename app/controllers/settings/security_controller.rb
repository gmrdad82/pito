# Phase 25 — 01a. Read-only security dashboard.
#
# Surfaces 2FA status (off in this sub-spec — TOTP ships in 01e) and a
# short summary of recent login attempts. The attempt log itself
# (paginated, filterable) lives at
# `/settings/security/attempts` (`Settings::Security::AttemptsController`).
#
# Auth: same `Sessions::AuthConcern` gate as every other settings
# surface. There is no per-user scoping on the attempt list — pito is
# single-install, multi-user (ADR 0003), and every authenticated user
# sees every install-wide attempt.
#
# Phase 25 — 01b. Adds the trusted-locations count + active-pending
# count to the dashboard. These two numbers tell the operator at a
# glance whether the pending state machine is doing something it
# shouldn't.
class Settings::SecurityController < ApplicationController
  RECENT_LIMIT = 10

  def show
    @recent_attempts = LoginAttempt.recent.limit(RECENT_LIMIT)
    @failed_in_last_24h = LoginAttempt.failed.since(24.hours.ago).count
    @blocked_in_last_24h = LoginAttempt.blocked_results.since(24.hours.ago).count
    @active_blocks_count = BlockedLocation.active.count
    @trusted_locations_count = TrustedLocation.count
    @pending_sessions_count = Session.pending_within_window.count
    @twofa_enabled = false # 01e flips this on once TOTP enrollment lands.
  end
end
