# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for a "schedule this video?" confirmation.
      # Mirrors Pito::MessageBuilder::Video::DeleteConfirmation.
      # The update + YouTube write-through happen in Pito::Confirmation::Executor
      # on `#confirm video_schedule`.
      module ScheduleConfirmation
        module_function

        # @param video        [::Video]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @param when:        [Time]   the parsed UTC publish time.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(video, conversation:, when: nil)
          publish_time = binding.local_variable_get(:when)
          when_label   = publish_time.strftime("%Y-%m-%d %H:%M UTC")
          payload = {
            "command"     => "video_schedule",
            "body"        => Pito::Copy.render("pito.copy.videos.schedule_confirm",
                                               { title: video.title, when: when_label }),
            "html"        => false,
            "video_id"    => video.id,
            "video_title" => video.title,
            "publish_at"  => publish_time.utc.iso8601
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end
      end
    end
  end
end
