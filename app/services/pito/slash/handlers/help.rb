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
      # `Pito::Slash::HelpBuilder` which renders the witty nonsense man page.
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
                body:           Pito::Copy.render("pito.copy.help.body"),
                expand_label:   I18n.t("pito.slash.help.expand_label"),
                collapse_label: I18n.t("pito.slash.help.collapse_label"),
                sections:       help_sections
              }
            }
          ])
        end

        def help_sections
          slash_section + keybindings_section
        end

        # Build one section per auth group from the grammar registry.
        # Iterates Pito::Grammar::Registry.specs(namespace: :slash) so new slash
        # verbs appear automatically — no manual YAML sync required.
        def slash_section
          specs = Pito::Grammar::Registry.specs(namespace: :slash)
          rows  = specs.map do |spec|
            desc = spec.description_key.present? ? I18n.t(spec.description_key, default: "") : ""
            { key: "/#{spec.name}", value: desc }
          end.sort_by { |r| r[:key] }

          [ {
            title: I18n.t("pito.slash.help.sections.commands.title"),
            rows:  rows
          } ]
        end

        # Keybindings that are NOT already surfaced in copy/locales.
        # Sourced from pito.slash.help.keybindings locale key so the list
        # is maintainable without touching Ruby.
        def keybindings_section
          rows = I18n.t("pito.slash.help.keybindings").map do |shortcut, description|
            { key: shortcut.to_s, value: description }
          end
          return [] if rows.empty?

          [ {
            title: I18n.t("pito.slash.help.sections.keybindings.title"),
            rows:  rows
          } ]
        end
      end
    end
  end
end
