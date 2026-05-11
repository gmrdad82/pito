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
class Settings::SecurityController < ApplicationController
  RECENT_LIMIT = 10

  def show
    @recent_attempts = LoginAttempt.recent.limit(RECENT_LIMIT)
    @failed_in_last_24h = LoginAttempt.failed.since(24.hours.ago).count
    @blocked_in_last_24h = LoginAttempt.blocked_results.since(24.hours.ago).count
    @active_blocks_count = BlockedLocation.active.count
    @twofa_enabled = false # 01e flips this on once TOTP enrollment lands.
  end
end
