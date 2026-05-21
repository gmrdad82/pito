# Phase 25 — 01g (LD-11). Exponential backoff calculator for the
# login throttle.
#
# Builds on top of `Rack::Attack`'s per-IP and per-account throttles.
# When a throttle bucket trips, the controller calls `record_trip!`
# with the discriminant (a normalized IP or email-digest key). The
# next trip on the same key doubles the backoff window, capped at
# `MAX_BACKOFF`. Each trip refreshes the TTL — if the user does not
# trip again within `MAX_BACKOFF`, the bucket forgets the history and
# the next trip starts from `BASE_BACKOFF`.
#
# Storage: `Rack::Attack.cache.store` (the shared Redis / MemoryStore
# backing the rest of the throttle bookkeeping). Fail-open on cache
# errors — a logging glitch must not deadlock the auth path.
#
# Contract:
#
#     Pito::Auth::BackoffCalculator.record_trip!(key: "ip:1.2.3.4")
#       => 60        # seconds until the next attempt is allowed
#     Pito::Auth::BackoffCalculator.record_trip!(key: "ip:1.2.3.4")
#       => 120       # doubled
#     ...
#     Pito::Auth::BackoffCalculator.record_trip!(key: "ip:1.2.3.4")
#       => 3600      # capped at MAX_BACKOFF
#
#     Pito::Auth::BackoffCalculator.seconds_remaining(key: "ip:1.2.3.4")
#       => Integer (seconds until the bucket clears, 0 if clear)
#
#     Pito::Auth::BackoffCalculator.reset!(key: "ip:1.2.3.4")
#       => true      # zero the trip count; called on successful login
#                    # for the per-email key.
module Pito
  module Auth
    class BackoffCalculator
      BASE_BACKOFF = 60          # 1 minute
      MAX_BACKOFF  = 60 * 60     # 1 hour
      NS           = "pito:login_backoff".freeze

      # Returns the new backoff window (seconds) the caller should advertise.
      # Increments the trip counter for `key` (creating the bucket on first
      # trip), persists with TTL = window so the bucket auto-forgets when
      # the user stops tripping.
      def self.record_trip!(key:)
        return BASE_BACKOFF if key.to_s.empty?

        cache_key = bucket_key(key)
        count = cache.increment(cache_key, 1, expires_in: MAX_BACKOFF).to_i
        count = 1 if count <= 0
        backoff_for_count(count)
      rescue StandardError => e
        Rails.logger.warn("[Pito::Auth::BackoffCalculator] record_trip! failed: #{e.class}: #{e.message}")
        BASE_BACKOFF
      end

      # Number of seconds the caller should still wait before allowing the
      # next attempt. Returns 0 when the bucket has expired or never tripped.
      def self.seconds_remaining(key:)
        return 0 if key.to_s.empty?

        cache_key = bucket_key(key)
        count = cache.read(cache_key).to_i
        return 0 if count <= 0

        backoff_for_count(count)
      rescue StandardError
        0
      end

      # Zero the bucket. Called on a successful login (LD-11 flaw test in
      # the spec: a legitimate user who typo'd a few times should not stay
      # locked out indefinitely).
      def self.reset!(key:)
        return false if key.to_s.empty?

        cache_key = bucket_key(key)
        cache.delete(cache_key)
        true
      rescue StandardError
        false
      end

      def self.backoff_for_count(count)
        n = count.to_i
        n = 1 if n < 1
        # 2^(n-1) * BASE_BACKOFF, capped at MAX_BACKOFF. The doubling is
        # 60s, 120s, 240s, 480s, 960s, 1920s, 3600s (capped).
        candidate = BASE_BACKOFF * (2**(n - 1))
        [ candidate, MAX_BACKOFF ].min
      end

      def self.bucket_key(key)
        "#{NS}:#{key}"
      end

      def self.cache
        Rack::Attack.cache.store
      end
    end
  end
end
