# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for a "sync this video from YouTube?" confirmation.
      # The executor branch (`sync_video` in Pito::Confirmation::Executor) enqueues
      # SyncVideoJob on confirm, which fetches YouTube fields + stats and broadcasts
      # a summary.
      module SyncConfirmation
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, conversation:)
          payload = {
            "command"         => "sync_video",
            "body"            => Pito::Copy.render("pito.copy.sync.video_confirm", { title: video.title }),
            "html"            => false,
            "video_id"        => video.id,
            "video_title"     => video.title,
            "conversation_id" => conversation.id
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
