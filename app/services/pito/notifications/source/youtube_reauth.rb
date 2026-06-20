# frozen_string_literal: true

module Pito
  module Notifications
    module Source
      # Reauth reminder for a YoutubeConnection that lost its grant
      # (`needs_reauth = true`, e.g. after a 401 / expired refresh token).
      #
      # Message-only with an unread-dedup: while a reminder is still unread we
      # don't create a duplicate, so a perpetually-disconnected channel isn't
      # spammed. Reconnecting clears `needs_reauth`, so the reminders stop.
      #
      # Fired by the daily `YoutubeReauthCheckJob` backstop AND, the moment a 401
      # flips a connection, by the live sync / remote-write flows
      # (`YoutubeConnection#flag_needs_reauth!`).
      module YoutubeReauth
        module_function

        # @param connection [YoutubeConnection, nil]
        # @return [Notification, nil] the created notification, or nil when the
        #   connection is nil or an unread reminder for it already exists.
        def report!(connection)
          return nil if connection.nil?

          message = message_for(connection)
          return nil if Notification.unread.where(message:).exists?

          Notification.create!(message:, level: "warning")
        end

        # Names the connection's channels (or its email when none) so the operator
        # knows which to reconnect.
        def message_for(connection)
          names = connection.channels.filter_map { |c| c.handle.presence || c.title.presence }
          who   = names.any? ? names.join(", ") : connection.email
          "YouTube re-auth needed for #{who} — reconnect via /connect."
        end
      end
    end
  end
end
