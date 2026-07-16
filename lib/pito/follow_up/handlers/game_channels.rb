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

          # tools.yml decides availability — `show` is this card's only declared tool
          # (NOT a hardcoded check). `show` needs its own no-follow-up-context dispatch.
          return undeclared_action(action) unless declared?(action)

          # Dispatch as free-chat (no follow_up context) with the "channel" noun
          # so that Show's `channel_noun?` check fires and `channel_ref` reads
          # the @handle directly from message.raw — independent of the source
          # event's game_id context. nl_eligible: false — RECONSTRUCTED body,
          # never owner-typed free text; the channel branch doesn't opt into
          # nl_soft_fail today, but this keeps the contract future-proof
          # (mirrors GameSimilar; 3.0.1 reconciliation fix).
          result = Pito::Dispatch::Router.call(
            input:          "show channel #{args}",
            conversation:   conversation,
            channel:        channel,
            period:         period,
            viewport_width: viewport_width,
            nl_eligible:    false
          )
          Pito::FollowUp::ChatResultAdapter.call(result)
        end
      end
    end
  end
end
