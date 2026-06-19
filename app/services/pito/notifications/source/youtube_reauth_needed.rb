# Notifications data model + delivery channels.
#
# Source helper for `needs_reauth = true` flips on a YoutubeConnection.
# Idempotent on `("youtube_reauth_needed", "youtube-reauth-#{id}")` so
# repeated 401 storms don't spam the inbox; the row stays unread until
# operator action.
module Pito
  module Notifications
    module Source
      module YoutubeReauthNeeded
        EVENT_TYPE = "youtube_reauth_needed"
        REAUTH_URL = "/oauth/youtube/start"

        module_function

        # @param connection [YoutubeConnection]
        # @return [Notification]
        def report!(connection)
          payload = Pito::Notifications::PayloadBuilder.build(
            event_type: EVENT_TYPE,
            overrides: {
              title: "youtube re-auth needed: #{connection.email}",
              body: "the youtube connection lost its grant; reconnect to resume sync.",
              url: REAUTH_URL,
              event_payload: {
                "connection_id" => connection.id,
                "connection_email" => connection.email
              }
            }
          )

          Notification.find_or_create_by!(
            event_type: EVENT_TYPE,
            dedup_key: "youtube-reauth-#{connection.id}"
          ) do |n|
            n.kind = :youtube_reauth_needed
            n.severity = :urgent
            n.title = payload[:title]
            n.body = payload[:body]
            n.url = payload[:url]
            n.event_payload = payload[:event_payload]
            n.fires_at = Time.current
          end
        end
      end
    end
  end
end
