# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `farewell` chat tool — `bye` / `good bye` / `see'ya` /
      # `hasta luego` and friends (recognised as whole-input phrases by
      # Pito::Chat::Parser). Replies with a random witty sign-off from
      # `pito.copy.farewell`. Takes no arguments.
      class Farewell < Pito::Chat::Handler
        self.tool = :farewell
        self.description_key = "pito.chat.farewell.descriptions.farewell"

        def call
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: { text: Pito::Copy.render("pito.copy.farewell") } }
          ])
        end
      end
    end
  end
end
