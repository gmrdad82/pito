# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      class Help < Pito::Slash::Handler
        self.verb = :help
        self.description_key = "pito.slash.help.descriptions.help"

        grammar do
          auth :any
          description_key "pito.grammar.slash.help"
        end

        def call
          authenticated ? full_help : restricted_help
        end

        private

        def restricted_help
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                message_key: "pito.slash.help.unauthenticated"
              }
            }
          ])
        end

        def full_help
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                body:           I18n.t("pito.slash.help.body"),
                expand_label:   I18n.t("pito.slash.help.expand_label"),
                collapse_label: I18n.t("pito.slash.help.collapse_label"),
                sections:       help_sections
              }
            }
          ])
        end

        def help_sections
          I18n.t("pito.slash.help.sections").values.map do |section|
            {
              title: section[:title],
              rows:  section[:rows]
            }
          end
        end
      end
    end
  end
end
