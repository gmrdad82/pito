# frozen_string_literal: true

# Verifies a 6-digit TOTP code submitted via the chatbox (`/authenticate
# <code>`) and, on success, mints the encrypted session cookie.
#
# This is the single login entry point — there is no `/login` route.
# The owner authenticates by typing `/authenticate 123456` into the chat;
# the controller masks the code before echoing/persisting it and calls
# this service to verify + mint.
#
# Per-IP throttling (10 failures / 5 min) guards the 6-digit space since
# the app is exposed to the internet via cloudflared.
module Pito
  module Auth
    class ChatLogin
      Result = Data.define(:status, :session_data) do
        # status — :ok | :invalid | :throttled | :not_enrolled
        def authenticated?
          status == :ok
        end
      end

      def self.call(code:, request:)
        new(code:, request:).call
      end

      def initialize(code:, request:)
        @code = code.to_s.strip
        @request = request
      end

      def call
        ip = @request&.remote_ip.to_s

        return failure(:throttled) if SessionThrottle.exhausted?(ip)
        return failure(:not_enrolled) unless AppSetting.totp_enabled?

        if Pito::Auth::TotpVerifier.call(code: @code) == :ok
          data = Pito::Auth::SessionCookie.mint!(@request, totp_verified_at: Time.current)
          Result.new(status: :ok, session_data: data)
        else
          SessionThrottle.record_failure(ip)
          failure(:invalid)
        end
      end

      private

      def failure(status)
        Result.new(status:, session_data: nil)
      end
    end
  end
end
