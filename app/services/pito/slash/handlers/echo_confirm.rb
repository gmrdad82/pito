# frozen_string_literal: true

# DEMO — remove once a real confirmation-requiring handler exists.
# This handler exists solely to prove the NeedsConfirmation result type
# round-trips through the dispatcher → controller → broadcaster pipeline.

module Pito
  module Slash
    module Handlers
      class EchoConfirm < Pito::Slash::Handler
        self.verb = :confirm_demo
        self.description_key = "pito.slash.help.descriptions.confirm_demo"

        def call
          Pito::Slash::Result::NeedsConfirmation.new(
            prompt_key: "pito.slash.confirm_demo.prompt",
            prompt_args: {},
            command_text: "/confirm_demo"
          )
        end
      end
    end
  end
end
