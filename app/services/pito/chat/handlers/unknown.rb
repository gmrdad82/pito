# frozen_string_literal: true

# Fallback handler for chat input pito can't parse at all (no recognised verb,
# not a greeting/farewell) — e.g. "boo!", "I'm hungry".
#
# This is NOT an error: a from-the-start-unintelligible message gets a witty,
# slightly ironic `:system` reply from the `pito.copy.huh` dictionary, always
# nudging toward `help`. Errors are reserved for input pito DID understand but
# couldn't act on (a known verb with broken args/kwargs) — those come from the
# verb handlers themselves.
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
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.huh") } }
          ])
        end
      end
    end
  end
end
