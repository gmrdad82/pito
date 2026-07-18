# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the mass "schedule N vids?" confirmation (WP3).
      # Mirrors Pito::MessageBuilder::Video::ScheduleConfirmation, batched: ONE
      # confirmation card for the whole comma-separated batch (all-or-nothing).
      #
      # The transactional write-through happens in
      # Pito::Confirmation::Executor#confirm_video_schedule_mass on
      # `#<handle> confirm` — items asc, one transaction, save! per vid.
      module MassScheduleConfirmation
        module_function

        # @param items        [Array<Hash>] each { video: ::Video, publish_at: Time }
        #                     — any extra keys (e.g. :segment) are ignored.
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(items, conversation:)
          sorted = items.sort_by { |item| item[:publish_at] }

          payload = {
            "command"       => "video_schedule_mass",
            "body"          => Pito::Copy.render("pito.copy.videos.mass_schedule_confirm", { count: sorted.size }),
            "html"          => false,
            "items"         => sorted.map { |item| item_payload(item) },
            "expand_detail" => sorted.map { |item| expand_line(item) }
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end

        def item_payload(item)
          {
            "video_id"    => item[:video].id,
            "video_title" => item[:video].title,
            "publish_at"  => item[:publish_at].utc.iso8601
          }
        end

        def expand_line(item)
          "##{item[:video].id} #{item[:video].title} — #{Pito::Formatter::SyncStamp.call(item[:publish_at])}"
        end
      end
    end
  end
end
