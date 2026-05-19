# Phase 10 — MCP scope catalog collapse (ADR 0004).
# Phase 25 — 01d — added the `auth` scope.
# Phase 29 (MCP cut, 2026-05-19) — drops both the `dev` and `auth`
# scopes. With the MCP surface fully removed, the dev knowledge base
# tools (`list_docs`, `read_doc`, `save_note`) and the auth
# administration tools (login_attempts_*, blocked_locations_list,
# auth_audit_log_list, totp_status) are gone. The catalog collapses to
# a single scope, `app`, which gates the JSON API surface exposed to
# the Rust CLI and any future first-party clients.
#
# Single source of truth for token scopes across the entire stack. One
# scope:
#
#   - `app` — application data — channels, videos, projects, calendar, etc.
#
# `Scopes::ALL` is a frozen array captured at boot. Doorkeeper's
# initializer reads the constant directly because initializers can run
# before the autoloader is fully wired.
module Scopes
  APP = "app"

  DESCRIPTIONS = {
    APP => "application access. manage channels, videos, projects, and the calendar."
  }.freeze

  # The catalog. One entry today; the method form remains for callers
  # that pre-date the simplification and for forward compatibility if a
  # future scope is reintroduced.
  def self.all
    [ APP ].freeze
  end

  # Frozen array captured at boot. Doorkeeper's initializer reads this
  # constant directly because initializers can run before the
  # autoloader is fully wired.
  ALL = all
end
