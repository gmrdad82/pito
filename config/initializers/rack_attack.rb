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

Rack::Attack.blocklisted_responder = lambda do |_req|
  body = { error: "rate_limited", retry_after: ApiAuthThrottle::WINDOW.to_i }.to_json
  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => ApiAuthThrottle::WINDOW.to_i.to_s },
    [ body ]
  ]
end
