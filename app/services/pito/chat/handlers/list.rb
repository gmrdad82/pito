# frozen_string_literal: true

# FAKE DATA — returns hardcoded placeholder content.
# Real list logic arrives in a domain plan.
module Pito
  module Chat
    module Handlers
      class List < Pito::Chat::Handler
        self.verb = :list
        self.description_key = "pito.chat.list.descriptions.list"

        def call
          Pito::Chat::Result::Ok.new(events: [
            {
              kind: :assistant_text,
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
