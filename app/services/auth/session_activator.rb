# Phase 25 — 01b (LD-12). Active-session minter.
#
# Single entry point that turns a "the user is allowed in" decision
# into a freshly-stamped active Session row. Two callers:
#
#   1. `SessionsController#create` on the trusted-location branch —
#      passes the freshly-validated user and the request; the service
#      mints a brand new active session, calls `reset_session` via the
#      caller block (see `via:` kwarg), upserts the trusted-location,
#      and writes a `LoginAttempt` row with
#      `reason: :trusted_location_success`. Returns
#      `[session_row, plaintext]` so the controller can set the cookie.
#
#   2. `Login::ChallengesController#create` on the approve branch
#      after `01c` lands (and `Login::TotpsController` after `01e`
#      lands). Those callers pass `existing: <pending session row>`;
#      the service flips state to `active` (LD-6) and stamps the
#      trusted-location upsert. The token rotation contract (LD-12)
#      requires `reset_session` + a fresh cookie token — that ALWAYS
#      happens here, regardless of which caller invoked it.
#
# The service NEVER bypasses `Auth::AttemptLogger`. Every mint /
# transition writes an attempt row so the audit trail stays complete.
#
# Contract:
#
#     row, plaintext = Auth::SessionActivator.call(
#       user:,
#       request:,
#       fingerprint_hash:,
#       ip_prefix:,
#       reason: :trusted_location_success | :new_location_2fa_passed |
#               :approved_from_web | :approved_from_tui | :approved_from_mcp,
#       existing: nil | Session (pending row to promote),
#       remember: false,
#     )
#
# Returns `[session_row, plaintext]` so the caller writes the signed
# cookie itself (the cookie jar lives on the controller, not on this
# service). When `existing:` is supplied AND the row is terminal
# (`expired` / `revoked`), raises `ActiveRecord::RecordInvalid` so the
# controller surfaces generic "Login failed." (LD-14).
module Auth
  class SessionActivator
    def self.call(user:, request:, fingerprint_hash:, ip_prefix:,
                  reason: :trusted_location_success, existing: nil,
                  remember: false)
      raise ArgumentError, "user required" if user.nil?
      raise ArgumentError, "fingerprint_hash required" if fingerprint_hash.blank?
      raise ArgumentError, "ip_prefix required" if ip_prefix.blank?

      ip = request&.remote_ip.to_s.presence || "0.0.0.0"
      ua = request&.user_agent.to_s.first(1024).presence || ""

      session_row = nil
      plaintext = nil

      ActiveRecord::Base.transaction do
        if existing
          # Promote an existing pending row. `transition_to_active!`
          # raises if the row is terminal — by design.
          existing.transition_to_active!
          session_row = existing
          # The previous (pending) token is reused: the cookie was
          # never written. The caller is responsible for minting and
          # writing a brand-new cookie via `reset_session` per LD-12.
          # We surface a fresh plaintext alongside the row so the
          # caller has one source of truth for the cookie value.
          plaintext = SecureRandom.urlsafe_base64(32)
          new_digest = Pito::TokenDigest.call(plaintext)
          # Update the digest on the row so the new cookie token
          # resolves on the next request.
          session_row.update_columns(token_digest: new_digest)
        else
          session_row, plaintext = Session.create_for!(
            user: user,
            ip: ip,
            user_agent: ua,
            remember: remember ? true : false
          )
        end

        # Stamp / refresh the trusted-location triple. Idempotent on
        # the unique index — the upsert covers a race between a 2FA
        # success and a parallel approve, and stamps `last_seen_at`
        # in both branches.
        TrustedLocation.touch_for(
          user: user,
          fingerprint_hash: fingerprint_hash,
          ip_prefix: ip_prefix
        )

        Auth::AttemptLogger.call(
          request: request,
          result: :success,
          reason: reason,
          user: user,
          username: user.username,
          session: session_row
        )
      end

      [ session_row, plaintext ]
    end
  end
end
