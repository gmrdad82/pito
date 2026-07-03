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
      # `/themes` takes NO arguments — theme selection happens in the sidebar UI,
      # not via a slash arg. The grammar spec declares zero slots, so the
      # dispatcher's arity guard REJECTS any extra token (`too_many_args`); only a
      # bare `/themes` reaches this handler and opens the sidebar.
      class Theme < Pito::Slash::Handler
        self.verb        = :themes
        self.description_key = "pito.slash.theme.descriptions.theme"

        # Grammar (auth, client dispatch): config/pito/verbs.yml (T8.9).

        def call
          open_sidebar
        end

        private

        # Opens the theme picker Sidebar (Turbo Stream into #pito-sidebar).
        def open_sidebar
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
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
