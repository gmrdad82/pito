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
      #       branch calls `Video::EmbeddingIndexer.call(video, force: true)`.
      #       Mode: :append — the confirmation lands as a new event below the card.
      #
      #   #<handle> rm / delete
      #     → Delegated to Chat::Handlers::Delete via ToolDelegator.
      #
      #   #<handle> link [to] [game] <id|title>
      #     → Delegated to Chat::Handlers::Link via ToolDelegator. The handler
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
          # tools.yml decides availability (NOT a hardcoded list — that shadowed `game`).
          return undeclared_action(action) unless declared?(action)

          if action == "analyze"
            # Analyze THIS video (the detail card's single entity) — a follow-up-only
            # path (AnalyzeReply), not a chat tool, so it stays special-cased here.
            return Pito::FollowUp::AnalyzeReply.append(
              level: :vid, ids: [ event.payload["video_id"] ].compact, conversation:, period:
            )
          end

          # Every OTHER declared reply tool (game, at-a-glance, reindex, link/unlink,
          # schedule/publish/unlist, shinies, sync, …) routes through the SAME chat
          # handler via ToolDelegator — no per-tool branch, so a new segment tool
          # works on replies the moment tools.yml declares its reply.target.
          Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
        end
      end
    end
  end
end
