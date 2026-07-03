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
      #   #<handle> rm / delete
      #     → Delegated to Chat::Handlers::Delete via VerbDelegator.
      #
      #   #<handle> link [to] [game] <id|title>
      #     → Delegated to Chat::Handlers::Link via VerbDelegator. The handler
      #       reads video_id from the source event and the game ref from rest.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Video` resolves to the Pito::Video MODULE (not the ActiveRecord model).
      # Always use `::Video` for the model.
      class VideoDetail < Pito::FollowUp::Handler
        self.target "video_detail"

        # @param event        [Event]        the video-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, _args = parse_rest(rest)

          if action == "analyze"
            # Analyze THIS video (the detail card's single entity).
            return Pito::FollowUp::AnalyzeReply.append(
              level: :vid, ids: [ event.payload["video_id"] ].compact, conversation:, period:
            )
          end

          if %w[rm del delete reindex link unlink shinies sync publish pub unlist schedule].include?(action)
            return Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end

          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.video_detail.errors.invalid_action",
            message_args: { action: action }
          )
        end
      end
    end
  end
end
