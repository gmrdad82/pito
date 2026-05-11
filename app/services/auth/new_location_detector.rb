# Phase 25 — 01b (LD-5). New-location decision.
#
# Given a user + fingerprint_hash + ip_prefix triple, returns one of
# three symbols the `SessionsController` post-password-check branch
# consumes:
#
#   - `:trusted`       — the pair exists on `trusted_locations` for
#                        this user; mint a fresh active session
#                        (handled by `Auth::SessionActivator`).
#   - `:blocked_pair`  — the pair is on the auto-block list (active,
#                        not unblocked); regardless of trust status,
#                        the response is generic "Login failed."
#                        This branch takes precedence over `:trusted`
#                        so a previously-trusted device that the
#                        operator later blocked cannot bypass the
#                        block (defense-in-depth).
#   - `:new_location`  — no trusted row, no active block. The
#                        controller renders `/login/challenge` and
#                        offers TOTP / "ask for approval".
#
# Pure function. Does NOT mutate trust state, does NOT touch the
# audit log — both happen in the caller (the trusted-location upsert
# lives in `Auth::SessionActivator` so it stamps only on confirmed
# success; the attempt log row writes happen in
# `Auth::AttemptLogger`).
#
# Returns `:blocked_pair` only when the active-block check fires.
# `Auth::AttemptLogger` ALSO performs its own block-pair short-circuit
# on every authenticate POST — keeping both is intentional. The
# detector's decision drives the controller branch; the logger's
# rewrite ensures every persisted row is honest. Either layer alone
# would let a regression slip through; both together close it.
module Auth
  class NewLocationDetector
    # Public entry. Returns one of `:trusted` / `:new_location` /
    # `:blocked_pair`. Nil/blank inputs collapse to `:new_location`
    # (failing closed — the user gets challenged, never auto-trusted).
    def self.call(user:, fingerprint_hash:, ip_prefix:)
      return :new_location if user.nil? || fingerprint_hash.blank? || ip_prefix.blank?

      if BlockedLocation.for_pair?(fingerprint_hash, ip_prefix)
        :blocked_pair
      elsif TrustedLocation.trusted?(user, fingerprint_hash, ip_prefix)
        :trusted
      else
        :new_location
      end
    end
  end
end
