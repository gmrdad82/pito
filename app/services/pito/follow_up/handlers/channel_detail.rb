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
          # verbs.yml decides availability (NOT a hardcoded list — that shadowed the
          # games/vids/shinies segment verbs).
          return undeclared_action(action) unless declared?(action)

          # `#<handle> analyze` → analyze THIS channel (the detail card's entity) — a
          # follow-up-only path (AnalyzeReply), not a chat verb, so it stays here.
          if action == "analyze"
            ch = resolve_channel_from_event(event)
            return channel_not_found_error if ch.nil?

            return Pito::FollowUp::AnalyzeReply.append(
              level: :channel, ids: [ ch.id ], conversation:, period:
            )
          end

          # `#<handle> visit <channel|studio>` → open the YouTube page / Studio. A
          # follow-up-only verb (no chat equivalent), so it stays special-cased.
          if action == "visit"
            destination = DESTINATION_MAP[dest_word.to_s.downcase]
            if destination.nil?
              return Pito::FollowUp::Result::Error.new(
                message_key:  "pito.follow_up.channel_detail.errors.needs_destination",
                message_args: {}
              )
            end

            ch = resolve_channel_from_event(event)
            return channel_not_found_error if ch.nil?

            return Pito::FollowUp::Result::Append.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Channel::Visit.call(ch, conversation:, destination:) }
            ])
          end

          # Every OTHER reply verb this card declares in verbs.yml (games, vids/videos,
          # shinies, at-a-glance, sync, …) routes through the matrix-gated
          # VerbDelegator. verbs.yml `reply.targets` is the single source of truth —
          # NEVER reintroduce a hardcoded list (it silently shadowed the segment verbs).
          # Unknown actions get this target's invalid_action copy from there.
          Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
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
