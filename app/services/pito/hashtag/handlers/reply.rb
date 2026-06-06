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
      # When found, body tokens (the words after the handle) are normalised into
      # structured segment-edit operations via `Pito::Grammar::Normalizer.call_ops`
      # (`:hashtag` namespace) and included in the `ops:` payload field.
      #
      # Returns `Result::Ok` with `kind: :system` and the ops array (may be empty
      # when the body is blank or unrecognised by the grammar).
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

          ops = normalize_body_ops

          Pito::Hashtag::Result::Ok.new(events: [
            {
              kind: :system,
              payload: {
                message_key: "pito.hashtag.reply.acknowledged",
                message_args: { handle: full_handle },
                ops: ops
              }
            }
          ])
        end

        private

        # Normalise body_tokens into structured segment-edit operations.
        # Returns an Array of op hashes, e.g.:
        #   [{ name: :add, metric: ["ctr", "views"] }, { name: :remove, metric: ["subscribers"] }]
        # Returns [] when body is empty or the grammar registry has no hashtag specs.
        def normalize_body_ops
          tokens = message.body_tokens
          return [] if tokens.nil? || tokens.empty?

          matches = Pito::Grammar::Normalizer.call_ops(
            tokens,
            namespace: :hashtag,
            context:   conversation
          )

          matches.filter_map do |match|
            next unless match.matched?

            { name: match.name }.merge(match.values)
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
