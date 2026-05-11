# Phase 25 — 01a. View helpers for the attempt log surface.
#
# Result-to-copy mapping keeps the table + show page + future
# notification card aligned on one vocabulary. The destructive red is
# reserved for `blocked` (the only "dangerous" status per CLAUDE.md's
# red-only-for-destructive rule).
module LoginAttemptsHelper
  RESULT_LABELS = {
    "success"          => "success",
    "failed"           => "failed",
    "pending_approval" => "pending approval",
    "blocked"          => "blocked",
    "rate_limited"     => "rate limited"
  }.freeze

  REASON_LABELS = {
    "wrong_password"           => "wrong password",
    "unknown_account"          => "unknown account",
    "new_location_pending"     => "new location, awaiting approval",
    "new_location_2fa_passed"  => "new location, 2FA passed",
    "trusted_location_success" => "trusted location",
    "blocked_pair"             => "blocked location",
    "rate_limited"             => "rate limited",
    "twofa_failed"             => "2FA failed",
    "approved_from_web"        => "approved via web",
    "approved_from_tui"        => "approved via TUI",
    "approved_from_mcp"        => "approved via MCP",
    "blocked_from_web"         => "blocked via web",
    "blocked_from_tui"         => "blocked via TUI",
    "blocked_from_mcp"         => "blocked via MCP",
    "pending_expired"          => "pending request expired"
  }.freeze

  def login_attempt_result_label(attempt)
    RESULT_LABELS[attempt.result.to_s] || attempt.result.to_s
  end

  def login_attempt_reason_label(attempt)
    REASON_LABELS[attempt.reason.to_s] || attempt.reason.to_s.tr("_", " ")
  end

  # Plain-text geo summary used inside the table cell. Returns
  # "location unknown" when no geo data is present.
  def login_attempt_geo_label(attempt)
    attempt.geo_summary.presence || "location unknown"
  end

  # CSS class applied to the result badge cell. Only `blocked` gets the
  # destructive-red treatment (per the project's red-only-for-
  # destructive rule). Success uses no class (default body color);
  # failed uses muted (`text-muted`) so the red stays meaningful.
  def login_attempt_result_css(attempt)
    case attempt.result.to_s
    when "blocked"          then "text-danger"
    when "failed"           then "text-muted"
    when "rate_limited"     then "text-muted"
    when "pending_approval" then ""
    else ""
    end
  end
end
