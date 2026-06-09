# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for a "delete this video?" confirmation.
      # Mirrors Pito::MessageBuilder::Game::DeleteConfirmation exactly.
      # The destroy happens in Pito::Confirmation::Executor on `#<handle> confirm`.
      module DeleteConfirmation
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, conversation:)
          payload = {
            "command"     => "video_delete",
            "body"        => Pito::Copy.render("pito.copy.videos.delete_confirm", { title: video.title }),
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
