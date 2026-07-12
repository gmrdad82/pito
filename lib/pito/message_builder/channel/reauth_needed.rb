# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for the "reauth needed" enhanced message.
      #
      # Called when one or more connected channels have `youtube_connection.needs_reauth?`
      # true after a `list channels` command. Emitted as a second `:enhanced` event so
      # the user sees the normal channel list PLUS a targeted reconnect reminder.
      #
      # Not follow-up-able — this is informational only.
      module ReauthNeeded
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channels [Array<::Channel>] non-empty subset whose connections need reauth.
        # @return [Hash] string-keyed html payload.
        def call(channels)
          header = ERB::Util.html_escape(Pito::Copy.render("pito.copy.channels.reauth_header"))
          lines = channels.map do |ch|
            Pito::Copy.render("pito.copy.channels.reauth_line", handle: ERB::Util.html_escape(ch.handle))
          end
          html_payload(body: ([ header ] + lines).join("<br>"))
        end
      end
    end
  end
end
