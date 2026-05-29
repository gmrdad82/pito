# Phase 12 — Step A (6a-sessions-and-login-ui.md) — failed-login bucket.
#
# Failed-login bucket (10 / 5min per IP). `SessionsController#create` calls
# `record_failure(ip)` on every failure path; the rack-attack `blocklist`
# block reads the same counter via `exhausted?`.
module SessionThrottle
  LIMIT  = 10
  WINDOW = 5.minutes

  module_function

  def bucket_key(ip)
    window_index = (Time.now.to_i / WINDOW.to_i)
    "pito:login_failed:#{window_index}:#{ip}"
  end

  def record_failure(ip)
    return if ip.to_s.empty?

    key = bucket_key(ip)
    Rack::Attack.cache.store.increment(key, 1, expires_in: WINDOW)
  rescue StandardError
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
