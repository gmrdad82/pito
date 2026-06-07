# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for a channel visit message.
      #
      # Renders Pito::Channel::VisitComponent in one of two states:
      #   :visiting (default) — shimmer + hidden anchor auto-clicked once by the
      #     pito--auto-visit controller, which then POSTs to consume the event.
      #   :visited — the consumed, follow-up state (no auto-click, manual link).
      #
      # The payload carries `channel_id` + `visit_state` so the consume endpoint
      # (Channels::VisitsController#consume) can rebuild the :visited payload.
      #
      # The :visiting payload is stamped follow-up-able (reply_target:
      # "channel_visit") when a conversation is given, so the System event renders
      # a stable `event_<id>` anchor — required for the consume mutation to land
      # live (replace_event) and for the JS to locate the event. The :visited
      # payload is NOT follow-up-able (nothing left to reply to), which also makes
      # a repeated consume a graceful no-op.
      module Visit
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel      [::Channel]
        # @param conversation [Conversation, nil] required to make :visiting anchorable.
        # @param state        [Symbol] :visiting (default) or :visited.
        # @return [Hash] string-keyed HTML payload.
        def call(channel, conversation: nil, state: :visiting)
          html    = render_component(Pito::Channel::VisitComponent.new(channel:, state:))
          payload = html_payload(body: html, channel_id: channel.id, visit_state: state.to_s)

          if state == :visiting && conversation
            Pito::FollowUp.make_followupable!(payload, target: "channel_visit", conversation: conversation)
          end

          payload
        end
      end
    end
  end
end
