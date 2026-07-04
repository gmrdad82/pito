module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      raw = cookies.encrypted[Pito::Auth::SessionCookie::COOKIE_NAME]

      if raw
        data = SessionDataWrapper.new(
          sid: raw["sid"],
          last_seen_at: raw["last_seen_at"]
        )
        # Authenticated session: identify by sid for per-session targeting.
        self.session_id = data.expired? ? guest_id : data.sid
      else
        # Unauthenticated: allow the connection so Turbo Streams work while
        # the /authenticate flow is not yet enforced end-to-end.
        self.session_id = guest_id
      end
    end

    # True when the encrypted session cookie identified this socket (fresh,
    # unexpired). Channels that carry conversation CONTENT (Pito::JsonChannel)
    # must reject guests — the HTML page withholds the scrollback from
    # anonymous visitors, and the cable must be no leakier than the page.
    def authenticated?
      session_id.present? && !session_id.start_with?("guest:")
    end

    private

    def guest_id
      "guest:#{request.session.id}"
    end

    SessionDataWrapper = Data.define(:sid, :last_seen_at) do
      def expired?(now = Time.current)
        last_seen_at.nil? || last_seen_at < now - Pito::Auth::SessionCookie::IDLE_TIMEOUT
      end
    end
  end
end
