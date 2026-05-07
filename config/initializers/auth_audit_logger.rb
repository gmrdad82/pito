# Phase 3 — Step B (5b-token-and-auth-concern.md) — auth audit logger.
#
# Dedicated logger for `Api::TokenAuthenticator` events (auth.success,
# auth.missing_token, auth.invalid_token, auth.revoked_token,
# auth.expired_token, auth.insufficient_scope, auth.throttled).
#
# Format: one JSON line per event. The call site already JSON-encodes
# the payload, so the formatter just appends a newline.
#
# Both Pumas (web + mcp) write to the same file. Logrotate is host-side
# concern (not configured here).
require "logger"

audit_path = Rails.root.join("log/auth_audit.log")
FileUtils.mkdir_p(File.dirname(audit_path))

AUTH_AUDIT_LOGGER = Logger.new(audit_path)
AUTH_AUDIT_LOGGER.formatter = ->(_severity, _time, _progname, msg) { "#{msg}\n" }
