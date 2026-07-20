# frozen_string_literal: true

# Handler for the `publish video <id>` chat tool.
#
# Emits a :confirmation event so the user can confirm before the change
# is applied locally and written through to YouTube via VideoRemoteStatusSync.
module Pito
  module Chat
    module Handlers
      class Publish < Pito::Chat::Handler
        self.tool = :publish
        self.description_key = "pito.chat.publish.descriptions.publish"

        NOUN_FILLERS = %w[vid vids video videos].freeze

        def call
          ref = extract_ref

          if ref.present?
            video = resolve_video(ref)
            return not_found(ref) unless video
          elsif follow_up?
            # `#<handle> publish` on a video card → publish that card's video.
            id = follow_up.source_event.payload.with_indifferent_access[:video_id]
            return needs_ref if id.blank?

            video = ::Video.find_by(id: id)
            return not_found("##{id}") unless video
          else
            return needs_ref
          end

          # Stage-time dry-run against the spacing LAW: publishing NOW is a
          # publish moment like any schedule — too close (<4h) to another
          # scheduled/published vid, or a third publish inside a rolling 24h,
          # gets refused here before the confirmation even renders (and again
          # for real at the executor's :publish-context save).
          violation = video.publish_now_violation
          if violation
            key, args = publish_violation_copy(violation, title: video.title)
            return Pito::Chat::Result::Ok.new(events: [
              { kind: :system, payload: Pito::MessageBuilder::Text.call(key, **args) }
            ])
          end

          Pito::Chat::Result::Ok.new(events: [
            { kind: :confirmation,
              payload: Pito::MessageBuilder::Video::PublishConfirmation.call(video, conversation: conversation) }
          ])
        end

        private

        # Publish-now flavors of the spacing-law copy (mirrors
        # Pito::Confirmation::Executor#publish_violation_copy so stage-time
        # and confirm-time rejections read the same).
        def publish_violation_copy(violation, title:)
          if violation[:kind] == :spacing
            [ "pito.copy.videos.publish_too_close",
              { title: title, other: violation[:title].to_s,
                when: Pito::Formatter::SyncStamp.call(violation[:at]) } ]
          else
            [ "pito.copy.videos.publish_day_cap",
              { title: title, others: Array(violation[:titles]).join(" and ") } ]
          end
        end

        def extract_ref
          message.body_tokens
                 .map(&:value)
                 .reject { |w| NOUN_FILLERS.include?(w.to_s.downcase) }
                 .join(" ")
                 .strip
        end

        def resolve_video(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Video.find_by(id: id) if id.match?(/\A\d+\z/)

          nil
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.publish.needs_ref", message_args: {})
        end

        def not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end
      end
    end
  end
end
