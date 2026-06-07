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
      # (Channels::VisitsController#consume) can rebuild the :visited payload and
      # guard against double-consumption.
      module Visit
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel [::Channel]
        # @param state   [Symbol] :visiting (default) or :visited.
        # @return [Hash] string-keyed HTML payload.
        def call(channel, state: :visiting)
          html = render_component(Pito::Channel::VisitComponent.new(channel:, state:))
          html_payload(body: html, channel_id: channel.id, visit_state: state.to_s)
        end
      end
    end
  end
end
