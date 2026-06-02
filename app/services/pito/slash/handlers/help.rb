# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      class Help < Pito::Slash::Handler
        self.verb = :help
        self.description_key = "pito.slash.help.descriptions.help"

        VISIBLE_COUNT = 5

        def call
          authenticated ? full_help : restricted_help
        end

        private

        # Unauthenticated: only instruct on /authenticate.
        def restricted_help
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: { text: I18n.t("pito.slash.help.unauthenticated") }
            }
          ])
        end

        # Authenticated: grouped commands, first VISIBLE_COUNT visible,
        # rest collapsed under ctrl+o (via expand_detail in payload).
        def full_help
          grouped = build_grouped_lines
          visible = grouped.first(VISIBLE_COUNT)
          overflow = grouped.drop(VISIBLE_COUNT)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                text:           I18n.t("pito.slash.help.intro", count: Pito::Slash::Registry.size),
                expand_lines:   visible.map { |l| l },
                expand_detail:  overflow.any? ? overflow : nil,
                expand_more_count: overflow.size
              }
            }
          ])
        end

        def build_grouped_lines
          lines = []
          Pito::Slash::Registry.registered_verbs.sort.each do |verb|
            handler_class = Pito::Slash::Registry.lookup(verb)
            lines << "/#{verb}  —  #{I18n.t(handler_class.description_key)}"
          end
          lines
        end
      end
    end
  end
end
