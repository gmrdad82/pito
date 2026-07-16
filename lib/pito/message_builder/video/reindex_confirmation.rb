# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for a "reindex this video?" confirmation.
      #
      # Emitted when the user replies `#<handle> reindex` to a video-detail event.
      # The executor branch (`video_reindex` in Pito::Confirmation::Executor) calls
      # Video::EmbeddingIndexer.call(video, force: true) on confirm.
      module ReindexConfirmation
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, conversation:)
          payload = {
            "command"     => "video_reindex",
            "body"        => Pito::Copy.render("pito.copy.videos.reindex_confirm", { title: video.title }),
            "html"        => false,
            "video_id"    => video.id,
            "video_title" => video.title
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
