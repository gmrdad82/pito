# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for a channel-visit message (reply_target: "channel_visit").
      #
      # The visit message is appended by ChannelList in its :visiting state and
      # stamped follow-up-able so it carries a stable `event_<id>` anchor. The
      # pito--auto-visit controller clicks the link once, then POSTs to
      # Channels::VisitsController#consume, which runs THIS handler through the
      # standard FollowUpDispatchJob mutation path:
      #
      #   #<handle> consume → Mutation(kind: system_follow_up, payload: :visited)
      #
      # The dispatch job persists the mutation + broadcasts replace_event, so the
      # System component flips to its :visited (surface) state live AND on refresh.
      #
      # Mode :mutate — transforms the source event in place; no echo, no new turn.
      # Idempotent: once consumed the payload is no longer follow-up-able, so a
      # repeat dispatch resolves no target and no-ops.
      class ChannelVisit < Pito::FollowUp::Handler
        self.target   "channel_visit"
        self.internal true

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil) # rubocop:disable Lint/UnusedMethodArgument
          action, _args = parse_rest(rest)

          # verbs.yml decides availability — `consume` is this card's only declared
          # verb (an internal visit-consume step), not a hardcoded check.
          return undeclared_action(action) unless declared?(action)

          channel = ::Channel.find_by(id: event.payload["channel_id"])
          unless channel
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.channel_visit.errors.channel_not_found",
              message_args: {}
            )
          end

          # Preserve the destination that was stamped when the :visiting payload
          # was built so the :visited [view] link points to the same URL.
          dest_str    = event.payload["visit_destination"].to_s
          destination = %w[studio channel].include?(dest_str) ? dest_str.to_sym : :channel

          Pito::FollowUp::Result::Mutation.new(
            kind:    :system_follow_up,
            payload: Pito::MessageBuilder::Channel::Visit.call(channel, state: :visited, destination:)
          )
        end
      end
    end
  end
end
