# Active-session minter.
#
# Single entry point that turns a "the user is allowed in" decision
# into a freshly-stamped active Session row. Callers:
#
#   1. `SessionsController#create` on the no-TOTP / first-login branch
#      — passes the freshly-validated user and the request; the service
#      mints a brand new active session and returns
#      `[session_row, plaintext]` so the controller can set the cookie.
#
#   2. `Login::TotpChallengesController#create` after a valid 6-digit
#      or backup code. Same shape — mints a fresh active session.
#
# Post-Phase-25 rollback. The trusted-location upsert + LoginAttempt
# write are gone. The activator's sole responsibility is now session
# minting. High-level audit lives in `Pito::Auth::AuditLogger` and is the
# caller's responsibility.
#
# 2026-05-16 (sessions revamp). The `remember:` keyword + the
# `sessions.remember` column it threaded into are gone. Cookies are
# session-only now.
module Pito
  module Auth
    class SessionActivator
      def self.call(user:, request:)
        raise ArgumentError, "user required" if user.nil?

        ip = request&.remote_ip.to_s.presence || "0.0.0.0"
        ua = request&.user_agent.to_s.first(1024).presence || ""

        Session.create_for!(
          user: user,
          ip: ip,
          user_agent: ua
        )
      end
    end
  end
end
