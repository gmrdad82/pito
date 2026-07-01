# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/notifications` — opens the notifications sidebar panel,
      # the slash-command equivalent of Ctrl+/.
      #
      # The handler broadcasts the same #pito-sidebar update that
      # GET /notifications serves over HTTP, by rendering the shared
      # app/views/notifications/_panel.html.erb partial via the broadcaster.
      #
      # `/notifications --help` never reaches this handler: the universal slash
      # `--help` interceptor (Pito::Slash::HelpBuilder) handles it BEFORE the
      # handler runs and renders the man-style help page.
      #
      # Takes NO arguments — it only opens the sidebar panel (no backend dispatch).
      # The grammar spec declares zero slots, so the dispatcher's arity guard
      # REJECTS any extra token (`too_many_args`); only the bare command opens the
      # panel. The canonical verb is `:notifications` (shown/autosuggested in the
      # palette + catalog); `:notifs` is kept as an alias (owner-decided).
      class Notifications < Pito::Slash::Handler
        self.verb        = :notifications
        self.description_key = "pito.slash.notifications.descriptions.notifications"

        grammar do
          aliases :notifs
          auth :authenticated_only
          description_key "pito.grammar.slash.notifications"
        end

        def call
          open_sidebar
        end

        private

        # Broadcasts the notifications panel into #pito-sidebar via the cable,
        # then returns a Result with a brief status text.
        def open_sidebar
          Pito::Stream::Broadcaster.new(conversation:).broadcast_notifications_sidebar

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                sidebar_open: "notifications",
                text:         I18n.t("pito.slash.notifications.sidebar.opening")
              }
            }
          ])
        end
      end
    end
  end
end
