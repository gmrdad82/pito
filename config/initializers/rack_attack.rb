# Phase 3 — Step B (5b-token-and-auth-concern.md) — failed-auth throttle.
#
# Goal: 10 failed bearer-token lookups per 5 minutes per IP → 429.
# Successful lookups never burn the bucket.
#
# Implementation: Rack::Attack provides the cache store and the standard
# 429 response shape. The actual counter is bumped from
# `Api::TokenAuthenticator` on every failure path, keyed by client IP.
# The middleware then short-circuits subsequent requests once the bucket
# is exhausted — Rack::Attack's `blocklist` block reads the same counter
# we wrote to.
#
# Why not a `throttle` block alone: the throttle block runs BEFORE the
# rack app is hit, so it can't observe the failure of the current request.
# Counting failures from inside the authenticator is the cleanest fit.

return unless defined?(Rack::Attack)

# Surfaces protected by bearer-token auth. Anything else falls through.
PROTECTED_PATH_RE = %r{\A(/mcp|/api/)}.freeze

# Tiny helper module so the authenticator and the throttle block agree on
# the cache key shape. The bucket rolls every ApiAuthThrottle::WINDOW
# seconds.
module ApiAuthThrottle
  LIMIT  = 10
  WINDOW = 5.minutes

  module_function

  def bucket_key(ip)
    window_index = (Time.now.to_i / WINDOW.to_i)
    "pito:auth_failed:#{window_index}:#{ip}"
  end

  def record_failure(ip)
    return if ip.to_s.empty?

    key = bucket_key(ip)
    Rack::Attack.cache.store.increment(key, 1, expires_in: WINDOW)
  rescue StandardError
    # Cache failures must not break the request path. The throttle is a
    # soft defense, not a security boundary.
    nil
  end

  def exhausted?(ip)
    return false if ip.to_s.empty?

    key = bucket_key(ip)
    count = Rack::Attack.cache.store.read(key).to_i
    count >= LIMIT
  rescue StandardError
    false
  end
end

if Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
else
  Rack::Attack.cache.store = Rails.cache
end

Rack::Attack.blocklist("over-failed-auth-limit") do |req|
  next false unless PROTECTED_PATH_RE.match?(req.path)
  ApiAuthThrottle.exhausted?(req.ip.to_s)
end

# Phase 12 — Step A (6a-sessions-and-login-ui.md). Failed-login throttle.
# Same shape as the bearer-token bucket above (10 / 5min / IP) but keyed
# off the `/login` POST surface only; successful logins do not burn the
# bucket because `SessionThrottle.record_failure` is invoked from
# `SessionsController` only on failure paths.
Rack::Attack.blocklist("over-failed-login-limit") do |req|
  next false unless req.path == "/login" && req.post?
  SessionThrottle.exhausted?(req.ip.to_s)
end

# Phase 12 — Step B (6b-doorkeeper-oauth-server.md). OAuth `/oauth/token`
# throttle: 30 requests per IP per 5 minutes. Higher than the login bucket
# because legitimate clients legitimately retry on transient errors and
# refresh inside the access-token TTL window.
Rack::Attack.throttle("oauth/token", limit: 30, period: 5.minutes) do |req|
  req.ip if req.path == "/oauth/token" && req.post?
end

# RFC 7591 — OAuth 2.0 Dynamic Client Registration. The
# `POST /oauth/register` endpoint is unauthenticated by design (single-user
# pito install behind cloudflared; the consent screen on
# `/oauth/authorize` is the actual security boundary). The throttle is a
# defense-in-depth control against a bot spraying registrations to fill
# the `oauth_applications` table. 5 / minute / IP is generous for the
# legitimate "rare manual MCP client setup" use case and tight for abuse.
Rack::Attack.throttle("oauth/register", limit: 5, period: 1.minute) do |req|
  req.ip if req.path == "/oauth/register" && req.post?
end

# Phase 25 — 01g (LD-11). Login throttles.
#
# Two throttles run side-by-side on the login surface:
#
#   * `login/ip`     — 5 POSTs / minute from one IP across the login
#                      endpoints (`/login`, `/login/totp`). Cheaper
#                      than the legacy 10-failure blocklist, runs in
#                      front of it, and trips even on RIGHT-password
#                      failure cases.
#   * `login/email`  — 10 POSTs / 15 minutes keyed on the lowercased
#                      `username` param. Hashed with SHA256 to keep
#                      the raw username out of cache keys (avoids
#                      leaking account-existence in cache snapshots).
#
# Post-Phase-25 rollback: the `/login/challenge` and `/login/pending`
# routes are gone, so they're dropped from LOGIN_PATHS. The
# `throttled_responder` no longer writes `LoginAttempt` rows (the
# table is gone); it just renders the generic 429 body.
LOGIN_PATHS = %w[/login /login/totp].freeze

Rack::Attack.throttle(
  "login/ip",
  limit: 5,
  period: 1.minute
) do |req|
  req.ip if LOGIN_PATHS.include?(req.path) && req.post?
end

Rack::Attack.throttle(
  "login/email",
  limit: 10,
  period: 15.minutes
) do |req|
  if req.path == "/login" && req.post?
    raw = req.params["username"].to_s.strip.downcase
    Digest::SHA256.hexdigest("login-username:#{raw}") if raw.present?
  end
end

# Phase 29 — Unit A2. Reset-password-via-2FA throttles. The recovery
# surface is treated with the same care as login: a per-IP throttle
# (mirrors `login/ip` — 5 / minute on POST + PATCH) and a per-username
# throttle (mirrors `login/email` — 10 / 15 minutes, SHA256-hashed
# username key, on POST). The `throttled_responder` below renders the
# same generic body as the `login/` branch for any `password/` match.
RESET_PASSWORD_PATH = "/password/reset"

Rack::Attack.throttle(
  "password/ip",
  limit: 5,
  period: 1.minute
) do |req|
  req.ip if req.path == RESET_PASSWORD_PATH && %w[POST PATCH].include?(req.request_method)
end

Rack::Attack.throttle(
  "password/username",
  limit: 10,
  period: 15.minutes
) do |req|
  if req.path == RESET_PASSWORD_PATH && req.post?
    raw = req.params["username"].to_s.strip.downcase
    Digest::SHA256.hexdigest("password-reset-username:#{raw}") if raw.present?
  end
end

# P25 follow-up — F1. Defense-in-depth throttle on the destructive
# TOTP-management endpoints under `/settings/security/totp*`. These
# routes are already gated by the standard session cookie AND ask for
# a fresh password + TOTP code on every destructive POST, but a stolen
# cookie could otherwise brute-force the password+TOTP combo at full
# request rate.
#
# Bucket: 10 POSTs / 15 minutes per IP — same cadence as the
# `login/email` bucket so attackers pay the same cost across both
# surfaces. Keyed on the request IP because the Rails session
# (`req.session[:user_id]`) is not consistently available at the
# Rack::Attack layer — rack-attack runs before Rails routes the
# request through `ActionDispatch::Session`. IP-keying covers the
# stolen-cookie threat (the attacker comes from one IP at a time)
# and is the standard pattern in this initializer.
#
# Affected paths (any POST):
#
#   - POST /settings/security/totp                       (atomic enroll finalize)
#
# After the 2026-05-16 cleanup the web surface collapsed to a single
# POST endpoint (atomic finalize). Disable + backup-code rotation
# moved to operator-only rake tasks and are NOT throttled at the
# web tier. The regex stays broad so any future verb-tunneled action
# under `/settings/security/totp*` still lands in the bucket.
TOTP_DESTRUCTIVE_PATH_RE = %r{\A/settings/security/totp(?:/|_|\z)}.freeze

Rack::Attack.throttle(
  "settings/totp",
  limit: 10,
  period: 15.minutes
) do |req|
  if TOTP_DESTRUCTIVE_PATH_RE.match?(req.path) &&
     %w[POST PATCH PUT DELETE].include?(req.request_method)
    req.ip
  end
end

# Phase 25 — 01g. Dev convenience — allowlist localhost so the maintainer
# is not throttled out of their own dev environment while iterating. NOT
# enabled in test (the throttle specs need to assert against 127.0.0.1)
# and NOT enabled in production (operators run pito behind Cloudflare;
# every legitimate ip is rewritten via `request.remote_ip`).
if Rails.env.development?
  Rack::Attack.safelist("dev/localhost") do |req|
    %w[127.0.0.1 ::1].include?(req.ip.to_s)
  end
end

Rack::Attack.blocklisted_responder = lambda do |_req|
  body = { error: "rate_limited", retry_after: ApiAuthThrottle::WINDOW.to_i }.to_json
  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => ApiAuthThrottle::WINDOW.to_i.to_s },
    [ body ]
  ]
end

# Phase 25 — 01g. Friendly responder for the new login throttles.
# Rack::Attack throttle hits land here BEFORE Rails routes. We render
# the generic `Login failed.` HTML (LD-14) so the user does NOT see
# the "you're being rate-limited" reason. The internal `LoginAttempt`
# row carries the precise reason.
Rack::Attack.throttled_responder = lambda do |req|
  match = req.env["rack.attack.matched"].to_s

  if match.start_with?("login/")
    # Post-Phase-25 rollback: no per-attempt forensic write — the
    # LoginAttempt table is gone. The throttle still short-circuits;
    # the operator audit trail for throttle trips lives in the
    # structured `AUTH_AUDIT_LOGGER` log only when the throttle hits
    # the in-controller path.
    retry_after =
      case match
      when "login/ip"    then 60
      when "login/email" then 15 * 60
      else                    60
      end

    body = <<~HTML
      <!doctype html>
      <html><head><meta charset="utf-8"><title>login failed.</title></head>
      <body><p>login failed.</p></body></html>
    HTML

    [
      429,
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Retry-After" => retry_after.to_s
      },
      [ body ]
    ]
  elsif match.start_with?("password/")
    # Phase 29 — Unit A2. Reset-password-via-2FA throttle hit. Generic
    # `reset failed.` HTML — same posture as the `login/` branch: no
    # "you're being rate-limited" reason, no account-existence oracle.
    # Post-Phase-25 rollback: the per-attempt forensic write is gone
    # along with the LoginAttempt table.
    retry_after = match == "password/username" ? 15 * 60 : 60

    body = <<~HTML
      <!doctype html>
      <html><head><meta charset="utf-8"><title>reset failed.</title></head>
      <body><p>reset failed.</p></body></html>
    HTML

    [
      429,
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Retry-After" => retry_after.to_s
      },
      [ body ]
    ]
  elsif match == "settings/totp"
    # P25 F1 — TOTP destructive endpoints throttle. Generic
    # "Too many attempts." HTML so we don't leak whether the password
    # or the TOTP code was the failing field, and don't mention
    # rate-limiting explicitly. Same shape as the login throttles.
    body = <<~HTML
      <!doctype html>
      <html><head><meta charset="utf-8"><title>too many attempts.</title></head>
      <body><p>too many attempts. try again in a few minutes.</p></body></html>
    HTML

    [
      429,
      {
        "Content-Type" => "text/html; charset=utf-8",
        "Retry-After" => (15 * 60).to_s
      },
      [ body ]
    ]
  else
    body = { error: "rate_limited" }.to_json
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => "60" },
      [ body ]
    ]
  end
end
