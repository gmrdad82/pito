# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for an "update this vid's description/tags on
      # YouTube?" confirmation. Mirrors PublishConfirmation. The local write +
      # the field-restricted YouTube push happen in Pito::Confirmation::Executor
      # on `#confirm video_metadata`.
      module MetadataConfirmation
        module_function

        PREVIEW_CHARS = 120

        # @param video        [::Video]
        # @param field        [String] "description" | "tags"
        # @param value        [String, Array<String>] staged value (tags: Array)
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, field:, value:, conversation:)
          payload = {
            "command"      => "video_metadata",
            "body"         => Pito::Copy.render("pito.copy.videos.metadata_confirm", {
              title: video.title, field: field, preview: preview(value)
            }),
            "html"         => false,
            "video_id"     => video.id,
            "video_title"  => video.title,
            "field"        => field,
            "staged_value" => value
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end

        def preview(value)
          text = value.is_a?(Array) ? value.join(", ") : value.to_s
          text.length > PREVIEW_CHARS ? "#{text[0, PREVIEW_CHARS]}…" : text
        end
      end
    end
  end
end
