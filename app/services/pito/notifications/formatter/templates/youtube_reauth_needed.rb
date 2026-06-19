# Notification formatter.
#
# Template for the `youtube_reauth_needed` notification kind.
#
# Required `event_payload` keys: `connection_id`, `connection_email`.
module Pito
  module Notifications
    module Formatter
      module Templates
        class YoutubeReauthNeeded < Base
          REAUTH_PATH = "/oauth/youtube/start"

          def title
            "youtube re-auth needed: #{fetch(:connection_email, placeholder('connection email'))}"
          end

          def body
            email = fetch(:connection_email, placeholder("connection email"))
            "the youtube oauth grant for #{email} expired or was revoked. " \
              "[re-authorize](#{REAUTH_PATH})."
          end

          def url
            REAUTH_PATH
          end
        end
      end
    end
  end
end
