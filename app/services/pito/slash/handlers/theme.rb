# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/themes` — opens the theme picker Sidebar. That's the only
      # behavior. Theme switching and previewing happen entirely within the
      # Sidebar (PATCH /settings/theme); there are no subcommands or arguments.
      #
      # `/themes --help` never reaches this handler: the universal slash `--help`
      # interceptor (Pito::Slash::HelpBuilder) handles it BEFORE the handler runs
      # and renders the "manual's manual" easter egg (same as `/help --help`).
      #
      # Any extra tokens after `/themes` are ignored — the command is lenient and
      # always opens the sidebar.
      class Theme < Pito::Slash::Handler
        self.verb        = :themes
        self.description_key = "pito.slash.theme.descriptions.theme"

        grammar do
          auth :authenticated_only
          description_key "pito.grammar.slash.theme"
        end

        def call
          open_sidebar
        end

        private

        # Opens the theme picker Sidebar (Turbo Stream into #pito-sidebar).
        def open_sidebar
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "system",
              payload: {
                sidebar_open: "theme",
                text:         I18n.t("pito.slash.theme.sidebar.opening")
              }
            }
          ])
        end
      end
    end
  end
end
