# frozen_string_literal: true

module Pito
  module Hashtag
    module Handlers
      # Handler for `#<confirmation-handle> [ops …]` hashtag input.
      #
      # Resolves the confirmation handle against `conversation.events` (matching on
      # `payload->>'confirmation_handle'`).  If no event is found, returns
      # `Result::Error` with key `pito.hashtag.reply.not_found`.
      #
      # Returns `Result::Ok` with `kind: :system` and an empty `ops:` array.
      # (The old metric-ops normalisation path has been removed; all live follow-up
      # dispatching now routes through `FollowUp::Router` + `FollowUpDispatchJob`.)
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
                message_args: { handle: full_handle },
                ops: []
              }
            }
          ])
        end
      end
    end
  end
end
