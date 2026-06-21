# frozen_string_literal: true

module Pito
  module Analytics
    # Signature-keyed analytics cache with async fan-out coordination.
    #
    # == Status model
    #
    #   pending  — computation in flight (or just claimed).
    #   ready    — result available; may be expired (treat as missing).
    #   failed   — last computation errored.
    #   missing  — no row, or ready-but-expired (logical, not stored).
    #
    # == Async fan-out pattern
    #
    #   sig = "channel:stats:28d"
    #   case Pito::Analytics::Cache.claim(sig)
    #   when :claimed then AnalyticsComputeJob.perform_later(sig)
    #   when :pending then nil              # job already running
    #   when :ready   then Cache.read(sig)  # already computed
    #   end
    #
    # == Synchronous convenience
    #
    #   result = Pito::Analytics::Cache.fetch(sig, ttl: 1.hour) { compute }
    #
    # == Thread safety
    #
    # claim uses the unique index to ensure only one caller wins the race:
    # the first INSERT wins (:claimed); concurrent callers hit RecordNotUnique
    # and fall back to :pending.  For expired/failed rows an atomic
    # UPDATE … WHERE NOT status = 'pending' achieves the same effect.
    module Cache
      # Maximum length of a stored error message (characters).
      ERROR_MAX = 2_000

      module_function

      # Returns the cached payload Hash when the row is ready and unexpired;
      # nil in all other cases (missing, pending, failed, expired).
      #
      # @param signature [String]
      # @return [Hash, nil]
      def read(signature)
        row = AnalyticsCache.find_by(signature: signature)
        return nil unless row&.live?

        row.payload
      end

      # Returns the logical status of the cache entry.
      # A ready-but-expired entry is reported as :missing.
      #
      # @param signature [String]
      # @return [Symbol] :ready | :pending | :failed | :missing
      def status(signature)
        row = AnalyticsCache.find_by(signature: signature)
        return :missing if row.nil?
        return :missing if row.status == "ready" && row.expired?

        row.status.to_sym
      end

      # Race-safe dedup gate for async work.
      #
      # Evaluates whether the caller should start computing:
      #   :claimed  — this caller won the race; MUST call store or fail.
      #   :pending  — another caller is computing; wait or subscribe.
      #   :ready    — a fresh result already exists; call read to retrieve it.
      #
      # Race safety: the unique index on signature ensures only one INSERT
      # succeeds when multiple callers arrive simultaneously.  For the
      # expired/failed case, a conditional UPDATE (WHERE NOT pending) is the
      # atomic arbiter.
      #
      # @param signature [String]
      # @return [Symbol] :claimed | :pending | :ready
      def claim(signature)
        row = AnalyticsCache.find_by(signature: signature)

        if row.nil?
          begin
            AnalyticsCache.create!(signature: signature, status: "pending")
            return :claimed
          rescue ActiveRecord::RecordNotUnique
            # Another worker inserted first — re-read and fall through.
            row = AnalyticsCache.find_by!(signature: signature)
          end
        end

        return :ready   if row.live?
        return :pending if row.status == "pending"

        # Row is expired or failed — try to atomically reclaim.
        # The WHERE NOT pending clause ensures only one concurrent caller wins.
        updated = AnalyticsCache
          .where(id: row.id)
          .where.not(status: "pending")
          .update_all(
            status:     "pending",
            payload:    nil,
            error:      nil,
            expires_at: nil,
            updated_at: Time.current
          )

        updated > 0 ? :claimed : :pending
      end

      # Upserts the cache row to ready with the given payload and TTL.
      #
      # @param signature [String]
      # @param payload   [Hash]
      # @param ttl:      [ActiveSupport::Duration, Numeric] seconds or duration
      def store(signature, payload, ttl:)
        AnalyticsCache.upsert(
          {
            signature:  signature,
            status:     "ready",
            payload:    payload,
            expires_at: Time.current + ttl,
            error:      nil
          },
          unique_by:   :signature,
          update_only: %i[status payload expires_at error]
        )
      end

      # Marks the row as failed and records a (truncated) error message.
      #
      # @param signature [String]
      # @param error:    [String, #to_s]
      def fail(signature, error:)
        message = error.to_s.truncate(ERROR_MAX)
        AnalyticsCache.upsert(
          {
            signature: signature,
            status:    "failed",
            error:     message,
            payload:   nil
          },
          unique_by:   :signature,
          update_only: %i[status error payload]
        )
      end

      # Synchronous convenience wrapper.
      #
      # Returns the cached payload if the entry is ready and unexpired.
      # Otherwise yields, stores the result with the given TTL, and returns it.
      # If the block raises, the entry is marked failed and the exception
      # is re-raised.
      #
      # @param signature [String]
      # @param ttl:      [ActiveSupport::Duration, Numeric]
      # @return [Hash] the cached or freshly computed payload
      def fetch(signature, ttl:)
        cached = read(signature)
        return cached unless cached.nil?

        result = yield
        store(signature, result, ttl: ttl)
        result
      rescue => e
        self.fail(signature, error: e.message)
        raise
      end

      # Lazy GC: deletes all rows whose expires_at has elapsed.
      #
      # @return [Integer] number of rows deleted
      def sweep
        AnalyticsCache
          .where("expires_at IS NOT NULL AND expires_at < ?", Time.current)
          .delete_all
      end
    end
  end
end
