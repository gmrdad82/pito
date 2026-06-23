# Z2a (2026-05-25). Verifies a 6-digit TOTP code against the singleton
# AppSetting seed.
#
# Post-Z1: there is no User model. The seed lives on AppSetting's
# singleton row (`AppSetting.totp_seed`). The replay watermark
# (`totp_last_used_step`) also lives on the singleton row.
#
# Returns `:ok` on a match, `:invalid` on every other case (empty
# code, malformed input, wrong code, expired window, no seed enrolled).
# Never raises on input — the caller surfaces a generic "login failed."
# on `:invalid`.
#
# Replay defense (RFC 6238 §5.2): a code is bound to a 30-second step
# window; drift tolerance widens the attack envelope to ~60 s. We track
# the highest-numbered step ever successfully verified in
# `AppSetting.singleton_row.totp_last_used_step` and reject any code
# that resolves to a step <= that watermark.
module Pito
  module Auth
    class TotpVerifier
      DRIFT_BEHIND_SECONDS = 30
      STEP_SECONDS         = 30

      # @param code [String] 6-digit TOTP string from the login form.
      # @return [:ok, :invalid]
      def self.call(code:)
        normalized = code.to_s.strip

        # Development-only convenience: a fixed dummy code logs in without an
        # authenticator app (and without enrolling a seed), so `/login 123456`
        # just works on a dev box. Defaults to "123456"; override via
        # PITO_DEV_TOTP_CODE, or disable with "" / "off". The real ROTP path
        # below still works alongside it. Double-guarded on Rails.env.development?
        # so it is IMPOSSIBLE to accept the dummy in test/production.
        dev_code = dev_totp_code
        if dev_code && ActiveSupport::SecurityUtils.secure_compare(normalized, dev_code)
          return :ok
        end

        seed = AppSetting.totp_seed
        return :invalid if seed.blank?

        return :invalid unless normalized.match?(/\A\d{6}\z/)

        begin
          totp = ROTP::TOTP.new(seed)
          matched_at = totp.verify(normalized, drift_behind: DRIFT_BEHIND_SECONDS)
          return :invalid if matched_at.nil?

          step = matched_at.to_i / STEP_SECONDS
          row  = AppSetting.singleton_row
          last = row.totp_last_used_step

          if last.present? && step <= last
            # Replay or stale-drift-window attempt.
            return :invalid
          end

          # `update_columns` bypasses validations + callbacks: the
          # watermark is an internal monotonic counter.
          row.update_columns(totp_last_used_step: step)
          :ok
        rescue StandardError => e
          Rails.logger.warn("[Pito::Auth::TotpVerifier] verify failed: #{e.class}: #{e.message}")
          :invalid
        end
      end

      # The active development-only dummy login code, or nil when it must not
      # apply. Returns nil outside development (hard guard), and when the
      # operator disables it via PITO_DEV_TOTP_CODE="" / "off".
      def self.dev_totp_code
        return nil unless Rails.env.development?

        raw = ENV.fetch("PITO_DEV_TOTP_CODE", "123456").to_s.strip
        return nil if raw.empty? || raw.casecmp?("off")

        raw
      end
      private_class_method :dev_totp_code
    end
  end
end
