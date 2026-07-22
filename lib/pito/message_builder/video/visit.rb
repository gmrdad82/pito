# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for a video visit message.
      #
      # Renders Pito::Video::VisitComponent in one of two states:
      #   :visiting (default) — shimmer + hidden anchor auto-clicked once by the
      #     pito--auto-visit controller, which then POSTs to consume the event.
      #   :visited — the consumed, follow-up state (no auto-click, manual link).
      #
      # The payload carries `video_id` + `visit_state` so the consume endpoint
      # (Videos::VisitsController#consume) can rebuild the :visited payload.
      #
      # The :visiting payload sets `reply_target: "video_visit"` (so the
      # FollowUpDispatchJob can route to the handler) and `anchor: true` (so
      # SystemComponent renders the stable `event_<id>` DOM anchor required for
      # replace_event to land live). It does NOT set `reply_handle` — the handler
      # is internal and must never appear as a user-typeable #hashtag.
      # The :visited payload carries neither, making a repeated consume a graceful
      # no-op (Registry.for returns nil → DispatchJob warns + returns).
      module Visit
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation, nil] unused; kept for call-site compat.
        # @param state        [Symbol] :visiting (default) or :visited.
        # @param destination  [Symbol] :youtube (default) or :studio.
        # @return [Hash] string-keyed HTML payload.
        def call(video, conversation: nil, state: :visiting, destination: :youtube)
          html    = render_component(Pito::Video::VisitComponent.new(video:, state:, destination:))
          payload = html_payload(
            body:             html,
            video_id:         video.id,
            visit_state:      state.to_s,
            visit_destination: destination.to_s
          )

          if state == :visiting
            payload["reply_target"] = "video_visit"
            payload["anchor"]       = true
          end

          payload
        end
      end
    end
  end
end
