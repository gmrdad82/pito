# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list channels` messages (reply_target: "channel_list").
      #
      # The list stamps each channel card with its @handle, so the user can reply:
      #
      #   #<handle> shinies @<channel_handle> — show achievements for the channel.
      #
      # To visit a channel's YouTube page or Studio, first `show channel @<handle>`
      # then reply `#<card_handle> visit channel` or `#<card_handle> visit studio`.
      #
      # Mode :append — adds a new message below; the list stays follow-up-able so
      # the user can query several channels in turn.
      class ChannelList < Pito::FollowUp::Handler
        self.target "channel_list"
        self.mode   :append
        self.actions "shinies"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, _ref = parse_rest(rest)

          case action
          when "shinies"
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_list.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end
      end
    end
  end
end
