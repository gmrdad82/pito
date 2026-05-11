# Phase 25 — 01d. Soft-unblock a `(fingerprint, ip_prefix)` pair.
#
# Counterpart to `Auth::LoginAttemptBlocker`. Stamps the row's
# `unblocked_at` + `unblocked_by_user_id` so the audit history is
# preserved (the row stays in the table — full purge lives in
# `Auth::BlockedLocationPurger`). Subsequent attempts from the pair
# pass the `BlockedLocation.for_pair?` short-circuit and resume the
# normal login path (re-evaluating trusted-location / pending logic).
#
# Contract (two callable shapes):
#
#     Auth::BlockedLocationUnblocker.call(
#       blocked_location:,
#       acting_user:,
#       source: :web | :tui | :mcp,
#     )
#
#     Auth::BlockedLocationUnblocker.call(
#       fingerprint_hash:,
#       ip_prefix:,
#       acting_user:,
#       source: :web | :tui | :mcp,
#     )
#
# When called with the pair shape the service looks up the *active*
# matching row (`unblocked_at IS NULL`). If no active row matches the
# pair, raises `NotBlocked`. If the row is already soft-unblocked,
# returns it as a no-op (idempotent) without writing an audit entry —
# the original unblock already captured the event.
#
# Concurrency: a row-level lock on the BlockedLocation serializes
# concurrent unblock calls so a duplicate audit row cannot land.
#
# Audit-logs via `Auth::AuditLogger` with `action: :unblock`. Defense-in-
# depth: only the caller-supplied `acting_user` is trusted; the service
# never reads request-supplied user ids.
module Auth
  class BlockedLocationUnblocker
    class NotBlocked < StandardError; end

    VALID_SOURCES = %i[web tui mcp].freeze

    def self.call(blocked_location: nil, fingerprint_hash: nil, ip_prefix: nil,
                  acting_user:, source:)
      raise ArgumentError, "acting_user required" if acting_user.nil?

      source_sym = source.to_sym
      unless VALID_SOURCES.include?(source_sym)
        raise ArgumentError, "invalid source: #{source.inspect}"
      end

      if blocked_location.nil?
        if fingerprint_hash.blank? || ip_prefix.blank?
          raise ArgumentError,
                "either blocked_location: or (fingerprint_hash: + ip_prefix:) required"
        end
      end

      already_unblocked = false
      row = nil

      ActiveRecord::Base.transaction do
        row = if blocked_location
          BlockedLocation.lock.find_by(id: blocked_location.id)
        else
          BlockedLocation
            .active
            .for_pair(fingerprint_hash, ip_prefix)
            .lock
            .first
        end

        if row.nil?
          # If we were given a specific row that no longer exists OR
          # the pair has no active match, raise so the caller can
          # surface a 404-shaped response.
          if blocked_location
            raise NotBlocked, "blocked_location row is gone"
          else
            raise NotBlocked, "no active block for the supplied pair"
          end
        end

        if row.unblocked_at.present?
          # Already-unblocked row — idempotent no-op. No audit row
          # because the original unblock already wrote one.
          already_unblocked = true
          next
        end

        row.update!(
          unblocked_at: Time.current,
          unblocked_by_user: acting_user
        )

        Auth::AuditLogger.call(
          acting_user: acting_user,
          source_surface: source_sym,
          action: :unblock,
          target: row,
          metadata: {
            "fingerprint_short" => row.fingerprint_hash.to_s[0, 12],
            "ip_prefix"         => row.ip_prefix
          }
        )
      end

      {
        blocked_location: row,
        already_unblocked: already_unblocked
      }
    end
  end
end
