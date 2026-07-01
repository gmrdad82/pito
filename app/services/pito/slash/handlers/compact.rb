# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/compact` — asks the owner to confirm context compaction.
      #
      # On confirm, CompactJob is enqueued (currently a no-op placeholder; real
      # compaction comes in a later release). On cancel the standard cancellation
      # copy is returned.
      #
      #   /compact           → confirmation event (follow-up-able)
      #   /compact --help    → man-style usage page
      #
      # authenticated_only — compacting is an owner action.
      class Compact < Pito::Slash::Handler
        self.verb            = :compact
        self.description_key = "pito.slash.compact.descriptions.compact"

        grammar do
          auth :authenticated_only
          description_key "pito.grammar.slash.compact"
        end

        def call
          return show_help if help?

          confirmation_event
        end

        private

        def confirmation_event
          payload = Pito::MessageBuilder::Compact::Confirmation.call(conversation:)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :confirmation,
              payload: payload
            }
          ])
        end

        def show_help
          body = Pito::MessageBuilder::ManPage.render(
            usage:  I18n.t("pito.slash.compact.help.usage"),
            groups: [
              [ "Options:", [ [ "--help", "Print this help message" ] ] ]
            ]
          )
          Pito::Slash::Result::Ok.new(events: [
            { kind: :system, payload: { "html" => true, "body" => body } }
          ])
        end
      end
    end
  end
end
