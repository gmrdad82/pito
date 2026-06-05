# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/help`.
      #
      # Behaviour varies by authentication state:
      # - **Authenticated**: returns a full sectioned help response (body + expand/collapse
      #   labels + sections array pulled from `pito.slash.help.sections` I18n data).
      # - **Unauthenticated**: returns a single `message_key: "pito.slash.help.unauthenticated"`
      #   event with the login instruction only.
      #
      # The `grammar` block declares `auth :any` so the dispatcher does not block
      # unauthenticated users — the handler itself branches on `authenticated`.
      #
      # `/help --help` is intercepted by the dispatcher and routed to
      # `Pito::Slash::HelpRenderer` which renders the witty nonsense dictionary.
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
