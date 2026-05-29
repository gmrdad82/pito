# Z2a (2026-05-25). Active-session minter.
#
# Post-Z1: there is no User model and no user_id on sessions. Mints a
# fresh Session row from the caller's request metadata and returns
# [session_row, plaintext] so the controller can write the cookie.
#
# Single caller: SessionsController#create after a successful TOTP or
# backup-code verification.
module Pito
  module Auth
    class SessionActivator
      # @param request [ActionDispatch::Request]
      # @return [[Session, String]] [session_row, plaintext_token]
      def self.call(request:)
        ip = request&.remote_ip.to_s.presence || "0.0.0.0"
        ua = request&.user_agent.to_s.first(1024).presence || ""

        Session.create_for!(ip: ip, user_agent: ua)
      end
    end
  end
end
