# Phase 13.2 — Analytics sync engine. Typed exceptions raised by
# `Youtube::AnalyticsClient`. Each maps to a specific retry-or-fail
# policy in the spec's error-handling matrix.
#
# - `AuthError` — HTTP 401. Job sets `connection.needs_reauth = true`
#   and exits cleanly. Sidekiq does NOT retry.
# - `RateLimitError` — HTTP 429. Sidekiq retries with exponential
#   backoff (max 5 attempts, base 30s, max 30 minutes).
# - `TransientError` — HTTP 5xx, network timeouts. Sidekiq retries.
# - `PermanentError` — HTTP 4xx other than 401/429, malformed
#   responses. Sidekiq does NOT retry.
module Youtube
  class AnalyticsClient
    class Error < StandardError; end
    class AuthError < Error; end
    class RateLimitError < Error; end
    class TransientError < Error; end
    class PermanentError < Error; end
  end
end
