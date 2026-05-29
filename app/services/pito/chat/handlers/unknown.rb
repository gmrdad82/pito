# frozen_string_literal: true

# Fallback handler for unrecognised chat input.
# Produces a "didn't understand" error event in the scrollback.
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
