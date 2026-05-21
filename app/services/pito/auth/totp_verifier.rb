# Phase 25 — 01e. Verifies a 6-digit TOTP code against a user's seed.
#
# Uses `ROTP::TOTP#verify` with `drift_behind: 1` so a code from the
# previous 30-second window still validates — the documented tolerance
# for authenticator-app clock skew. The default `drift_ahead` of 0 is
# kept so a future-window code (impossible without a clock-tampered
# attacker) is rejected.
#
# Returns `:ok` on a match, `:invalid` on every other case (empty
# code, malformed input, wrong code, expired window, user not
# enrolled). The verifier never raises on input — the caller surfaces
# a generic `Login failed.` (LD-14) on `:invalid` and re-renders the
# form.
#
# P25 follow-up — F9. Replay defense per RFC 6238 §5.2: "the verifier
# MUST NOT accept the second attempt of the OTP after the successful
# validation has been issued for the first OTP". A code is bound to
# a 30-second time-step window, but the drift tolerance widens the
# attack envelope to ~60 seconds. We track the highest-numbered step
# this user has ever successfully verified in `users.totp_last_used_step`
# and reject any code that resolves to a step `<=` that watermark.
# Effects:
#   - The same plaintext code cannot be replayed in the 60-s window.
#   - A code from an older drift window cannot be used after a newer
#     one has been accepted (monotonic step requirement).
#   - First-ever verify always accepts (watermark is nil).
module Pito
  module Auth
    class TotpVerifier
      DRIFT_BEHIND_SECONDS = 30
      STEP_SECONDS = 30

      def self.call(user:, code:)
        raise ArgumentError, "user required" if user.nil?

        seed = user.totp_seed_encrypted
        return :invalid if seed.blank?

        normalized = code.to_s.strip
        return :invalid unless normalized.match?(/\A\d{6}\z/)

        begin
          totp = ROTP::TOTP.new(seed)
          matched_at = totp.verify(normalized, drift_behind: DRIFT_BEHIND_SECONDS)
          return :invalid if matched_at.nil?

          # `matched_at` is the Unix-time start of the window ROTP
          # matched against. Dividing by the 30-s step yields the
          # canonical step index used for replay comparison.
          step = matched_at.to_i / STEP_SECONDS
          last = user.totp_last_used_step

          if last.present? && step <= last
            # Replay (or stale-drift-window) attempt — refuse without
            # updating the watermark.
            return :invalid
          end

          # `update_columns` bypasses validations + callbacks: the
          # watermark is an internal monotonic counter, not a
          # user-editable field, and we want this write to be cheap and
          # side-effect-free.
          user.update_columns(totp_last_used_step: step)
          :ok
        rescue StandardError => e
          Rails.logger.warn("[Pito::Auth::TotpVerifier] verify failed: #{e.class}: #{e.message}")
          :invalid
        end
      end
    end
  end
end
