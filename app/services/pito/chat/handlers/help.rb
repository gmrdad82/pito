# frozen_string_literal: true

# Handler for the `help` chat verb.
#
# Produces a System message listing every follow-up target and its accepted
# actions, grouped by entity (GAME, VIDEO, CHANNEL, THEME, CONFIRMATION).
# The content is IDENTICAL to the `#help` hashtag handler — both delegate to
# Pito::MessageBuilder::Help::FollowUpActions.
#
# The message is dynamic: it reads Pito::FollowUp::Registry at call time, so
# newly registered handlers appear automatically without code changes here.
module Pito
  module Chat
    module Handlers
      class Help < Pito::Chat::Handler
        self.verb = :help
        self.description_key = "pito.chat.help.descriptions.help"

        def call
          payload = Pito::MessageBuilder::Help::FollowUpActions.call

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: }
          ])
        end
      end
    end
  end
end
