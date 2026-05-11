# Phase 25 — 01a. Single entry point that the SessionsController calls
# on every authenticate POST. Composes fingerprint + ip_prefix + geo,
# parses the UA, checks the auto-block list, writes the LoginAttempt
# row, and (when geo was deferred) enqueues the backfill job.
#
# Contract:
#
#   row = Auth::AttemptLogger.call(
#     request:,
#     email: nil,
#     user:  nil,
#     result: :success | :failed | :pending_approval | :blocked,
#     reason: <one of LoginAttempt.reasons.keys>
#   )
#
# `email` is the raw email the user typed (logged on failure so the
# operator can correlate "someone tried `gmail@example.test` four
# times"). `user` is the resolved `User` row (nil when the email
# doesn't match any account).
#
# **Blocked-pair short-circuit.** When `result` is anything other than
# `:blocked` AND `BlockedLocation.for_pair?(fp, ip_prefix)` is true,
# the row is rewritten with `result: :blocked` and `reason: :blocked_pair`.
# This is what enforces LD-14 (every block-list hit looks the same to
# the user — generic "Login failed").
#
# The logger NEVER persists or logs raw passwords / their hashes. That
# is asserted by a flaw-class spec.
module Auth
  class AttemptLogger
    # Allowed `result` values for the public entry. Validated up front
    # so a typo in the controller surfaces during dispatch rather than
    # via an enum exception inside the transaction.
    ALLOWED_RESULTS = %i[success failed pending_approval blocked].freeze

    def self.call(request:, result:, reason:, user: nil, email: nil, notification: nil, session: nil)
      result = result.to_sym
      reason = reason.to_sym

      unless ALLOWED_RESULTS.include?(result)
        raise ArgumentError, "result must be one of #{ALLOWED_RESULTS.inspect} (got #{result.inspect})"
      end

      ip = request.remote_ip.to_s.presence || "0.0.0.0"
      ip_prefix = safe_prefix(ip)

      fingerprint_hash = Auth::FingerprintComposer.call(
        request: request,
        screen_hint: request.params["fp_screen"],
        locale_hint: request.params["fp_locale"]
      )

      Auth::GeoEnricher.reset_deferred!
      geo = Auth::GeoEnricher.call(ip)
      deferred_geo = Auth::GeoEnricher.deferred?

      ua_raw = request.user_agent.to_s.first(1024)
      ua_parts = Pito::Auth::UserAgentParser.call(ua_raw)

      # Blocked-pair check overrides any other result EXCEPT when the
      # caller has already decided the row is `:blocked` (then we trust
      # the caller's reason). This keeps the rate-limit / 2FA-failed
      # paths from being relabelled.
      blocked = result != :blocked && BlockedLocation.for_pair?(fingerprint_hash, ip_prefix)
      if blocked
        result = :blocked
        reason = :blocked_pair
      end

      attempt = nil

      ActiveRecord::Base.transaction do
        attempt = LoginAttempt.create!(
          user: user,
          email_attempted: email.presence,
          result: result,
          ip: ip,
          ip_prefix: ip_prefix,
          geo_city:    geo[:city],
          geo_region:  geo[:region],
          geo_country: geo[:country],
          user_agent: ua_raw.presence || "",
          browser: ua_parts[:browser],
          os:      ua_parts[:os],
          fingerprint_hash: fingerprint_hash,
          reason: reason,
          notification: notification,
          session: session
        )

        if blocked
          BlockedLocation.bump_attempt!(fingerprint_hash, ip_prefix)
        end
      end

      if deferred_geo && attempt && attempt.geo_country.blank?
        LoginAttemptGeoEnrichJob.perform_async(attempt.id)
      end

      attempt
    end

    # `request.remote_ip` can be blank in odd test setups; we still want
    # a deterministic prefix so the row writes without surprise. Fall
    # back to `0.0.0.0/24` for the unknown case rather than raising —
    # the audit row matters more than a perfectly clean prefix.
    def self.safe_prefix(ip)
      Pito::Auth::IpPrefix.call(ip)
    rescue ArgumentError
      "0.0.0.0/#{Pito::Auth::IpPrefix::IPV4_BITS}"
    end
  end
end
