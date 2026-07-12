# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `greet` chat tool — `hi` / `hello` / `hola` (any case,
      # via KeywordSanitizer). Replies with a random witty, helpful greeting from
      # `pito.copy.greeting` that orients a new user toward what pito can do.
      # Takes no arguments; extra words after the greeting are ignored.
      class Greeting < Pito::Chat::Handler
        self.tool = :greet
        self.description_key = "pito.chat.greeting.descriptions.greet"

        def call
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.greeting") } }
          ])
        end
      end
    end
  end
end
