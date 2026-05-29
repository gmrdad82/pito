module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :session_id

    def connect
      raw = cookies.encrypted[Pito::Auth::SessionCookie::COOKIE_NAME]
      return reject_unauthorized_connection unless raw

      data = SessionDataWrapper.new(raw)
      return reject_unauthorized_connection if data.expired?

      self.session_id = data.sid
    end

    SessionDataWrapper = Data.define(:sid, :last_seen_at) do
      def expired?(now = Time.current)
        last_seen_at.nil? || last_seen_at < now - Pito::Auth::SessionCookie::IDLE_TIMEOUT
      end
    end
  end
end
