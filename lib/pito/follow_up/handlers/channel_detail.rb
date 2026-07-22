# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for channel-detail events (reply_target: "channel_detail").
      #
      # The detail card (`show channel @handle`) is stamped follow-up-able by
      # `Pito::MessageBuilder::Channel::Detail.call`. The channel is resolved from
      # the card's own `channel_id` payload — no ref parsing needed.
      #
      #   #<handle> visit <destination> — opens the channel's YouTube page or
      #     Studio. Config-declared (tools.yml `visit.reply.targets.channel_detail`,
      #     ref: source_entity, args: destination) — routes through the SAME
      #     matrix-gated ToolDelegator every other reply tool this card accepts
      #     takes (T9: the DESTINATION_MAP special case retired in favor of
      #     Pito::Chat::Handlers::Visit, reached via Router). See that handler's
      #     class header for the destination vocabulary + legacy :channel mapping.
      #
      # An unrecognised action returns an invalid_action error.
      #
      # Mode :append — the visit card is added below; the detail card stays
      # follow-up-able so the user can visit channel AND studio in sequence.
      class ChannelDetail < Pito::FollowUp::Handler
        self.target "channel_detail"

        # @param event        [Event]        the channel-detail source event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, _args = parse_rest(rest)
          # tools.yml decides availability (NOT a hardcoded list — that shadowed the
          # games/vids/shinies segment tools).
          return undeclared_action(action) unless declared?(action)

          # `#<handle> analyze` → analyze THIS channel (the detail card's entity) — a
          # follow-up-only path (AnalyzeReply), not a chat tool, so it stays here.
          if action == "analyze"
            ch = resolve_channel_from_event(event)
            return channel_not_found_error if ch.nil?

            return Pito::FollowUp::AnalyzeReply.append(
              level: :channel, ids: [ ch.id ], conversation:, period:
            )
          end

          # Every OTHER reply tool this card declares in tools.yml (visit, games,
          # vids/videos, shinies, at-a-glance, sync, …) routes through the matrix-gated
          # ToolDelegator. tools.yml `reply.targets` is the single source of truth —
          # NEVER reintroduce a hardcoded list (it silently shadowed the segment tools).
          # Unknown actions get this target's invalid_action copy from there.
          Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
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
