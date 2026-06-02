# frozen_string_literal: true

# DEMO — Proves the Refine result type round-trips.
# Replace with proper routing when real refinement-capable handlers exist.
module Pito
  module Chat
    module Handlers
      class RefineDemo < Pito::Chat::Handler
        # No self.verb — not registered against any verb.
        # Invoked directly by the dispatcher's :refinement branch.

        def call
          Pito::Chat::Result::Refine.new(events: [
            {
              kind: :system,
              payload: {
                message_key: "pito.chat.refine_demo.acknowledged",
                message_args: { input: message.raw }
              }
            }
          ])
        end
      end
    end
  end
end
