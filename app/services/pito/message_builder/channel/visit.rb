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
      # The :visiting payload sets `reply_target: "channel_visit"` (so the
      # FollowUpDispatchJob can route to the handler) and `anchor: true` (so
      # SystemComponent renders the stable `event_<id>` DOM anchor required for
      # replace_event to land live). It does NOT set `reply_handle` — the handler
      # is internal and must never appear as a user-typeable #hashtag.
      # The :visited payload carries neither, making a repeated consume a graceful
      # no-op (Registry.for returns nil → DispatchJob warns + returns).
      module Visit
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel      [::Channel]
        # @param conversation [Conversation, nil] unused; kept for call-site compat.
        # @param state        [Symbol] :visiting (default) or :visited.
        # @return [Hash] string-keyed HTML payload.
        def call(channel, conversation: nil, state: :visiting)
          html    = render_component(Pito::Channel::VisitComponent.new(channel:, state:))
          payload = html_payload(body: html, channel_id: channel.id, visit_state: state.to_s)

          if state == :visiting
            payload["reply_target"] = "channel_visit"
            payload["anchor"]       = true
          end

          payload
        end
      end
    end
  end
end
