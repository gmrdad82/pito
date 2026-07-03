# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the CHANNEL MATCHES recommendations card
      # (reply_target: "game_channels").
      #
      # The channel-matches grid is stamped `reply_target: "game_channels"` by
      # `Pito::MessageBuilder::Game::Channels.call`. The user can reply:
      #
      #   #<handle> show @<handle>
      #     → Show the referenced channel by @handle (free-chat dispatch of
      #       `show channel @<handle>`). Returns the standard channel detail
      #       + analytics event set.
      class GameChannels < Pito::FollowUp::Handler
        self.target "game_channels"

        # @param event        [Event]        the channel-matches card event.
        # @param rest         [String]       text after `#<handle> ` (e.g. "show @gmrdad82").
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          unless action == "show"
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_channels.errors.invalid_action",
              message_args: { action: action }
            )
          end

          # Dispatch as free-chat (no follow_up context) with the "channel" noun
          # so that Show's `channel_noun?` check fires and `channel_ref` reads
          # the @handle directly from message.raw — independent of the source
          # event's game_id context.
          result = Pito::Chat::Dispatcher.call(
            input:          "show channel #{args}",
            conversation:   conversation,
            channel:        channel,
            period:         period,
            viewport_width: viewport_width
          )
          Pito::FollowUp::ChatResultAdapter.call(result)
        end
      end
    end
  end
end
