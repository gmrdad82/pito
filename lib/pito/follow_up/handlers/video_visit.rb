# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for a video-visit message (reply_target: "video_visit").
      #
      # The visit message is appended in its :visiting state and stamped
      # follow-up-able so it carries a stable `event_<id>` anchor. The
      # pito--auto-visit controller clicks the link once, then POSTs to
      # Videos::VisitsController#consume, which runs THIS handler through the
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
      class VideoVisit < Pito::FollowUp::Handler
        self.target   "video_visit"
        self.internal true

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil) # rubocop:disable Lint/UnusedMethodArgument
          action, _args = parse_rest(rest)

          # tools.yml decides availability — `consume` is this card's only declared
          # tool (an internal visit-consume step), not a hardcoded check.
          return undeclared_action(action) unless declared?(action)

          video = ::Video.find_by(id: event.payload["video_id"])
          unless video
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.video_visit.errors.video_not_found",
              message_args: {}
            )
          end

          # Preserve the destination that was stamped when the :visiting payload
          # was built so the :visited [view] link points to the same URL.
          dest_str    = event.payload["visit_destination"].to_s
          destination = %w[studio youtube].include?(dest_str) ? dest_str.to_sym : :youtube

          Pito::FollowUp::Result::Mutation.new(
            kind:    :system_follow_up,
            payload: Pito::MessageBuilder::Video::Visit.call(video, state: :visited, destination:)
          )
        end
      end
    end
  end
end
