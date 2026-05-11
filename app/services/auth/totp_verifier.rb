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
module Auth
  class TotpVerifier
    DRIFT_BEHIND_SECONDS = 30

    def self.call(user:, code:)
      raise ArgumentError, "user required" if user.nil?

      seed = user.totp_seed_encrypted
      return :invalid if seed.blank?

      normalized = code.to_s.strip
      return :invalid unless normalized.match?(/\A\d{6}\z/)

      begin
        totp = ROTP::TOTP.new(seed)
        matched_at = totp.verify(normalized, drift_behind: DRIFT_BEHIND_SECONDS)
        matched_at ? :ok : :invalid
      rescue StandardError => e
        Rails.logger.warn("[Auth::TotpVerifier] verify failed: #{e.class}: #{e.message}")
        :invalid
      end
    end
  end
end
