# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for channel-detail events (reply_target: "channel_detail").
      #
      # The detail card (`show channel @handle`) is stamped follow-up-able by
      # `Pito::MessageBuilder::Channel::Detail.call`. The channel is resolved from
      # the card's own `channel_id` payload — no ref parsing needed. The user
      # replies with a destination keyword:
      #
      #   #<handle> visit channel   — open the channel's YouTube page (also:
      #   #<handle> visit youtube       `youtube` or `yt` are accepted synonyms).
      #   #<handle> visit yt
      #
      #   #<handle> visit studio    — open YouTube Studio for the channel.
      #
      # A bare `#<handle> visit` (no destination) returns a needs_destination
      # error; an unrecognised action returns an invalid_action error.
      #
      # Mode :append — the visit card is added below; the detail card stays
      # follow-up-able so the user can visit channel AND studio in sequence.
      class ChannelDetail < Pito::FollowUp::Handler
        self.target "channel_detail"
        self.mode   :append
        self.actions "visit", "sync", "analyze"

        DESTINATION_MAP = {
          "channel" => :channel,
          "youtube" => :channel,
          "yt"      => :channel,
          "studio"  => :studio
        }.freeze

        # @param event        [Event]        the channel-detail source event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, dest_word = parse_rest(rest)

          # `#<handle> sync` → re-sync THIS channel (the chat sync handler reads the
          # card's channel_id from the follow-up context).
          if action == "sync"
            return Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end

          # `#<handle> analyze` → analyze THIS channel (the detail card's entity).
          if action == "analyze"
            ch = resolve_channel_from_event(event)
            return channel_not_found_error if ch.nil?

            return Pito::FollowUp::AnalyzeReply.append(
              level: :channel, ids: [ ch.id ], conversation:, period:
            )
          end

          unless action == "visit"
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end

          destination = DESTINATION_MAP[dest_word.to_s.downcase]
          if destination.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_detail.errors.needs_destination",
              message_args: {}
            )
          end

          ch = resolve_channel_from_event(event)
          return channel_not_found_error if ch.nil?

          Pito::FollowUp::Result::Append.new(events: [
            { kind: "system", payload: Pito::MessageBuilder::Channel::Visit.call(ch, conversation:, destination:) }
          ])
        end

        private

        # DetailMessage stamps `channel_id` into the payload.
        def resolve_channel_from_event(event)
          payload    = event.payload.with_indifferent_access
          channel_id = payload[:channel_id]
          return nil unless channel_id.present?

          ::Channel.find_by(id: channel_id)
        end

        def channel_not_found_error
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.channel_detail.errors.channel_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
