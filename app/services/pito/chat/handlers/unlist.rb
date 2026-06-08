# frozen_string_literal: true

# Handler for the `unlist video <id|title>` chat verb.
#
# Emits a :confirmation event so the user can confirm before the change
# is applied locally and written through to YouTube via VideoRemoteStatusSync.
module Pito
  module Chat
    module Handlers
      class Unlist < Pito::Chat::Handler
        self.verb = :unlist
        self.description_key = "pito.chat.unlist.descriptions.unlist"

        NOUN_FILLERS = %w[video videos].freeze

        def call
          ref = extract_ref
          return needs_ref if ref.blank?

          video = resolve_video(ref)
          return not_found(ref) unless video

          Pito::Chat::Result::Ok.new(events: [
            { kind: :confirmation,
              payload: Pito::MessageBuilder::Video::UnlistConfirmation.call(video, conversation: conversation) }
          ])
        end

        private

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

          ::Video.find_by("title ILIKE ?", ref)
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.unlist.needs_ref", message_args: {})
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
