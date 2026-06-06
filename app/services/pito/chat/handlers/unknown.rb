# frozen_string_literal: true

# Fallback handler for unrecognised chat input.
#
# Produces a `Result::Error` with key `pito.chat.errors.unknown_input` so
# the scrollback shows a "didn't understand" inline error.
#
# Does NOT register a verb — invoked directly by the dispatcher's `:unknown`
# branch after all other dispatch paths are exhausted.
module Pito
  module Chat
    module Handlers
      class Unknown < Pito::Chat::Handler
        # No self.verb — not registered against any verb.
        # Invoked directly by the dispatcher's :unknown branch.

        def call
          Pito::Chat::Result::Error.new(
            message_key: "pito.chat.errors.unknown_input",
            message_args: { input: message.raw }
          )
        end
      end
    end
  end
end
