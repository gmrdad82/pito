# frozen_string_literal: true

# Handler for the `#help` hashtag.
#
# Produces the SAME System message as the `help` chat verb — a grouped list of
# every follow-up target and its accepted actions.
#
# Wiring: the dispatcher extracts the stem word from any `#<stem>[-suffix]`
# input.  `#help` → stem `:help` → registered here as `self.handle = :help`.
# `Pito::Hashtag::Registry.register_all!` (called at boot) picks this class up
# automatically because it lives under `Pito::Hashtag::Handlers`.
#
# Body tokens (anything after `#help`) are ignored — the output is always the
# full follow-up-actions reference.
module Pito
  module Hashtag
    module Handlers
      class Help < Pito::Hashtag::Handler
        self.handle = :help

        def call
          payload = Pito::MessageBuilder::Help::FollowUpActions.call

          Pito::Hashtag::Result::Ok.new(events: [
            { kind: :system, payload: }
          ])
        end
      end
    end
  end
end
