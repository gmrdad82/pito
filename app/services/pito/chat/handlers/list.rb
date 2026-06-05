# frozen_string_literal: true

# Handler for the `list` chat verb.
#
# **FAKE DATA** — returns hardcoded placeholder content keyed at
# `pito.chat.list.fake_response`.  Real list logic (querying the conversation's
# video/channel scope) arrives in a domain plan.
module Pito
  module Chat
    module Handlers
      class List < Pito::Chat::Handler
        self.verb = :list
        self.description_key = "pito.chat.list.descriptions.list"

        def call
          Pito::Chat::Result::Ok.new(events: [
            {
              kind: :system,
              payload: {
                message_key: "pito.chat.list.fake_response",
                message_args: { count: 5, sample_title: "Sample video title" }
              }
            }
          ])
        end
      end
    end
  end
end
