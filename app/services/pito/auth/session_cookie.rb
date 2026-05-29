# frozen_string_literal: true

# Encrypted cookie that replaces the server-side Session row.
#
# The cookie holds all session state (sid, auth flags, timestamps).
# No DB lookup needed — the encrypted payload is self-validating.
#
# Idle expiry is checked at every read: if last_seen_at is older than
# IDLE_TIMEOUT the cookie is treated as absent (expired).
module Pito
  module Auth
    class SessionCookie
      COOKIE_NAME = :pito_session
      IDLE_TIMEOUT = 24.hours
      ACTIVITY_DEBOUNCE = 5.minutes

      # Immutable value object held in Current.session.
      SessionData = Data.define(:sid, :authenticated, :totp_verified_at, :created_at, :last_seen_at) do
        def expired?(now = Time.current)
          last_seen_at.nil? || last_seen_at < now - IDLE_TIMEOUT
        end
      end

      def self.from_request(request)
        new(request).read
      end

      def self.mint!(request, totp_verified_at: Time.current)
        now = Time.current
        data = SessionData.new(
          sid: SecureRandom.uuid,
          authenticated: true,
          totp_verified_at: totp_verified_at,
          created_at: now,
          last_seen_at: now
        )
        instance = new(request)
        instance.write(data)
        data
      end

      def initialize(request)
        @request = request
      end

      def read
        raw = read_cookie
        return nil if raw.nil?

        data = SessionData.new(
          sid: raw["sid"],
          authenticated: raw["authenticated"],
          totp_verified_at: raw["totp_verified_at"],
          created_at: raw["created_at"],
          last_seen_at: raw["last_seen_at"]
        )

        return nil if data.expired?

        data
      rescue ActiveSupport::MessageVerifier::InvalidSignature,
             ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      def touch!(data)
        now = Time.current
        return data if data.last_seen_at.present? && data.last_seen_at >= ACTIVITY_DEBOUNCE.ago

        updated = data.with(last_seen_at: now)
        write(updated)
        updated
      end

      def clear!
        cookie_jar.delete(COOKIE_NAME)
      end

      def mark_totp_verified!(data, at: Time.current)
        updated = data.with(totp_verified_at: at, last_seen_at: at)
        write(updated)
        updated
      end

      def write(payload)
        cookie_jar.encrypted[COOKIE_NAME] = {
          value: {
            sid: payload.sid,
            authenticated: payload.authenticated,
            totp_verified_at: payload.totp_verified_at,
            created_at: payload.created_at,
            last_seen_at: payload.last_seen_at
          },
          httponly: true,
          same_site: :lax,
          secure: !Rails.env.test?
        }
      end

      private

      def read_cookie
        cookie_jar.encrypted[COOKIE_NAME]
      end

      def cookie_jar
        @request.cookie_jar
      end
    end
  end
end
