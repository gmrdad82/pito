# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      class Help < Pito::Slash::Handler
        self.verb = :help
        self.description_key = "pito.slash.help.descriptions.help"

        def call
          events = []

          # Intro line: "N commands available."
          events << {
            kind: "assistant_text",
            payload: {
              message_key: "pito.slash.help.intro",
              message_args: { count: Pito::Slash::Registry.size }
            }
          }

          # One entry per registered handler: "/help — Show this help message"
          Pito::Slash::Registry.registered_verbs.sort.each do |verb|
            handler_class = Pito::Slash::Registry.lookup(verb)
            events << {
              kind: "assistant_text",
              payload: {
                message_key: "pito.slash.help.entry",
                message_args: {
                  verb: verb.to_s,
                  description: I18n.t(handler_class.description_key)
                }
              }
            }
          end

          Pito::Slash::Result::Ok.new(events:)
        end
      end
    end
  end
end
