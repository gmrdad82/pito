# Phase 14 §1 — IGDB rate limiter.
#
# Token-bucket gate with two caps:
#   - 4 requests per 1.0s rolling window (capacity 4, refill 4 per s).
#   - 8 concurrent in-flight requests.
#
# Process-local. Per spec Open Question #4, multi-process Sidekiq
# deploys may need a Redis-backed limiter; v1 trusts the
# `:concurrency: 5` cap in `config/sidekiq.yml` to keep aggregate
# throughput well under 4 req/s.
#
# `acquire(&block)` blocks until a window slot AND a concurrency
# slot are both available, runs the block, releases both. Block
# exceptions propagate; slots release in the `ensure`.
class Game
  module Igdb
    class RateLimiter
      DEFAULT_RATE     = 4
      DEFAULT_INTERVAL = 1.0
      DEFAULT_CONCURRENCY = 8

      class << self
        def shared
          @shared ||= new
        end

        def reset_shared!
          @shared = nil
        end
      end

      def initialize(rate: DEFAULT_RATE, interval: DEFAULT_INTERVAL, concurrency: DEFAULT_CONCURRENCY)
        @rate         = rate
        @interval     = interval
        @concurrency  = concurrency
        @timestamps   = []
        @in_flight    = 0
        @mutex        = Mutex.new
        @cond         = ConditionVariable.new
      end

      def acquire
        wait_for_slot
        begin
          yield if block_given?
        ensure
          release_slot
        end
      end

      private

      def wait_for_slot
        @mutex.synchronize do
          loop do
            prune_expired_timestamps
            if @timestamps.size < @rate && @in_flight < @concurrency
              @timestamps << monotonic_now
              @in_flight += 1
              return
            end

            if @in_flight >= @concurrency
              # Concurrency cap — wait for a release signal.
              @cond.wait(@mutex)
            else
              # Rate-window cap — sleep until the oldest timestamp
              # ages out. Use timed wait so signals from release_slot
              # can interrupt.
              wait_for = (@timestamps.first + @interval) - monotonic_now
              @cond.wait(@mutex, wait_for) if wait_for.positive?
            end
          end
        end
      end

      def release_slot
        @mutex.synchronize do
          @in_flight -= 1 if @in_flight.positive?
          @cond.broadcast
        end
      end

      def prune_expired_timestamps
        cutoff = monotonic_now - @interval
        @timestamps.shift while @timestamps.any? && @timestamps.first <= cutoff
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
