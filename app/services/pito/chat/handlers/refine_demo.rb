# frozen_string_literal: true

# Demonstration handler for the `Refine` result type.
#
# **DEMO** — Proves that `Pito::Chat::Result::Refine` round-trips through the
# dispatcher and job pipeline.  It does NOT register a verb (`self.verb` is
# intentionally absent) and is invoked directly by the dispatcher's
# `:refinement` branch when the current conversation has an open turn.
#
# Replace this handler with proper refinement-capable handlers once the
# domain model for incremental turn refinement is implemented.
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
