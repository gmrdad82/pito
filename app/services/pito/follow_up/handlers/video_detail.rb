# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for video-detail events (reply_target: "video_detail").
      #
      # The detail message is stamped `reply_target: "video_detail"` by
      # `Pito::MessageBuilder::Video::Detail`. The user can reply:
      #
      #   #<handle> reindex
      #     → Emit a confirmation event (`command: "video_reindex"`) whose executor
      #       branch calls `Video::VoyageIndexer.call(video, force: true)`.
      #       Mode: :append — the confirmation lands as a new event below the card.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Video` for the model.
      class VideoDetail < Pito::FollowUp::Handler
        self.target "video_detail"
        self.mode   :append
        self.actions "reindex"

        # @param event        [Event]        the video-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:)
          action, _args = parse_rest(rest)

          case action
          when "reindex"
            handle_reindex(event, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.video_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── reindex ────────────────────────────────────────────────────────────

        def handle_reindex(event, conversation)
          video = resolve_video_from_event(event)
          if video.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.video_detail.errors.video_not_found",
              message_args: {}
            )
          end

          payload = Pito::MessageBuilder::Video::ReindexConfirmation.call(video, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── helpers ────────────────────────────────────────────────────────────

        def resolve_video_from_event(event)
          payload = event.payload.with_indifferent_access
          video_id = payload[:video_id]
          return nil unless video_id.present?

          ::Video.find_by(id: video_id)
        end
      end
    end
  end
end
