# Phase 25 — 01g (LD-11). Writes a `LoginAttempt` row when
# `Rack::Attack` (or the in-controller throttle) trips on a login
# surface. Decoupled from `Auth::AttemptLogger` so the rate-limit
# hot path stays narrow and never re-enters the block-list lookup —
# a throttled request must never get relabeled as `:blocked_pair`.
#
# Contract:
#
#     Auth::RateLimitLogger.call(request:)
#     Auth::RateLimitLogger.call(
#       request: nil,
#       ip: "1.2.3.4",
#       user_agent: "...",
#       email: "you@example.com",
#       fingerprint_hash: "deadbeef..."   # optional; composed if missing
#     )
#
# Returns the persisted `LoginAttempt` row, or `nil` on any error
# (the rate-limit response must succeed even if logging fails).
module Auth
  class RateLimitLogger
    def self.call(request: nil, ip: nil, user_agent: nil, email: nil,
                  fingerprint_hash: nil)
      resolved_ip = (request&.remote_ip.to_s.presence) || ip.to_s.presence || "0.0.0.0"
      resolved_ua = (request&.user_agent.to_s.first(1024).presence) ||
                    user_agent.to_s.first(1024).presence ||
                    "(rate-limited)"

      resolved_fp = fingerprint_hash.presence
      if resolved_fp.blank?
        resolved_fp = begin
          Auth::FingerprintComposer.call(request: request)
        rescue StandardError
          # Composer requires a request; without one we synthesize a
          # rate-limit-discriminator hash so the row still satisfies
          # the validates :fingerprint_hash, length: { is: 64 } rule.
          Digest::SHA256.hexdigest("rate-limited:#{resolved_ip}:#{Time.now.to_i / 60}")
        end
      end

      resolved_prefix = begin
        Auth::AttemptLogger.safe_prefix(resolved_ip)
      rescue StandardError
        # Defensive — the prefix calculator should never throw, but
        # we'd rather log a row with a placeholder prefix than drop it.
        resolved_ip.include?(":") ? "::/64" : "0.0.0.0/24"
      end

      user_row = User.find_by(email: email.to_s.strip.downcase) if email.present?

      LoginAttempt.create!(
        user: user_row,
        email_attempted: email.to_s.strip.presence,
        result: :failed,
        reason: :rate_limited,
        ip: resolved_ip,
        ip_prefix: resolved_prefix,
        user_agent: resolved_ua,
        fingerprint_hash: resolved_fp
      )
    rescue StandardError => e
      Rails.logger.warn("[Auth::RateLimitLogger] failed: #{e.class}: #{e.message}")
      nil
    end
  end
end
