# Phase 25 — 01b. Adds an optional FK from `login_attempts` back to the
# `sessions` row the attempt spawned (when a session was actually
# minted or held pending).
#
# Why this column exists:
#
#   - On a trusted-location success, the row points at the freshly-minted
#     active session so `/settings/security/attempts/:id` can link to
#     `/settings/sessions/:id` for revoke.
#   - On a new-location "ask for approval" path, the row points at the
#     pending session so the holding page (`/login/pending`) can resolve
#     the attempt from the session and render the countdown.
#   - On a pending-expired sweep, the row written by the expirer carries
#     `session_id` so the operator can correlate "this session expired
#     pending approval" without scanning by timestamps.
#
# Nullable so the pre-existing 01a write paths (wrong password, unknown
# email, blocked pair) keep working unchanged.
class AddSessionIdToLoginAttempts < ActiveRecord::Migration[8.1]
  def change
    add_reference :login_attempts, :session, foreign_key: true, null: true, index: true
  end
end
