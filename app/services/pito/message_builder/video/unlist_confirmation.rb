# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for an "unlist this video?" confirmation.
      # Mirrors Pito::MessageBuilder::Video::DeleteConfirmation.
      # The update + YouTube write-through happen in Pito::Confirmation::Executor
      # on `#confirm video_unlist`.
      module UnlistConfirmation
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, conversation:)
          payload = {
            "command"     => "video_unlist",
            "body"        => Pito::Copy.render("pito.copy.videos.unlist_confirm", { title: video.title }),
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
