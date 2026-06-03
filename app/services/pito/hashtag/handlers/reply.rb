# frozen_string_literal: true

module Pito
  module Hashtag
    module Handlers
      class Reply < Pito::Hashtag::Handler
        self.handle = :reply

        def call
          full_handle = message.raw[1..].to_s.split(/\s+/, 2).first.to_s

          event = conversation.events
            .where("payload->>'confirmation_handle' = ?", full_handle)
            .first

          if event.nil?
            return Pito::Hashtag::Result::Error.new(
              message_key: "pito.hashtag.reply.not_found",
              message_args: { handle: full_handle }
            )
          end

          Pito::Hashtag::Result::Ok.new(events: [
            {
              kind: :system,
              payload: {
                message_key: "pito.hashtag.reply.acknowledged",
                message_args: { handle: full_handle }
              }
            }
          ])
        end
      end
    end
  end
end
