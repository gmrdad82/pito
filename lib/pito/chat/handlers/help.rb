# frozen_string_literal: true

# Handler for the `help` chat tool.
#
# Produces a simple, always-visible System message with a GAMES group (yellow
# title) and a single kv-table row pointing users to `list games --help`.
#
# The previous implementation delegated to Pito::MessageBuilder::Help::FollowUpActions
# (which produced a sections-based payload hidden behind the ctrl+| toggle).
# This replacement uses Pito::MessageBuilder::Help::Commands to render a
# plain html: true payload whose content is always visible.
#
# NOTE: The `#help` hashtag handler and any other callers still delegate to
# Pito::MessageBuilder::Help::FollowUpActions — only this chat tool changes.
module Pito
  module Chat
    module Handlers
      class Help < Pito::Chat::Handler
        self.tool = :help
        self.description_key = "pito.chat.help.descriptions.help"

        def call
          payload = Pito::MessageBuilder::Help::Commands.call

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: }
          ])
        end
      end
    end
  end
end
