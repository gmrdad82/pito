# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # Handler for `/games [subcommand] [title]`.
      #
      # Subcommands / dispatch table
      # ─────────────────────────────
      # `/games import [title]` — open the IGDB search import sidebar, prefilling
      #                           the search box with `title` if supplied.
      # `/games`  (bare)        — witty usage hint pointing to `/games import`.
      # `/games <unknown>`      — witty usage hint.
      # `/games --help`         — per-command usage text.
      #
      # The handler is `authenticated_only`: matching behaviour of all game/YouTube
      # commands (a user must be signed in to import a game).
      #
      # Opening the sidebar is done via a Turbo Stream fast-path in ChatController
      # (mirroring the `/themes` bare path). The handler returns a `sidebar_open`
      # system event that the ChatDispatchJob → Broadcaster renders.  The controller
      # intercepts `/games import` before the async pipeline and renders the partial
      # directly, so the handler itself is only exercised by the job path (e.g. tests).
      class Games < Pito::Slash::Handler
        self.verb            = :games
        self.description_key = "pito.slash.games.descriptions.games"
        self.validates_own_arity = true

        # Grammar (subcommand + title slots, auth): config/pito/verbs.yml (T8.9).

        SUBCOMMANDS = %w[import].freeze

        def call
          return show_help if help?

          raw_arg = invocation.args.first.to_s.strip.downcase

          case raw_arg
          when ""       then usage_hint
          when "import" then open_import_sidebar
          else
            # Unknown subcommand — witty usage
            usage_hint
          end
        end

        def show_help
          body = Pito::MessageBuilder::ManPage.render(
            usage:  I18n.t("pito.slash.games.help.usage"),
            groups: [
              [ "Subcommands:", [ [ "import", I18n.t("pito.slash.games.help.description") ] ] ],
              [ "Options:",     [ [ "--help", "Print this help message" ] ] ]
            ]
          )
          Pito::Slash::Result::Ok.new(events: [ {
            kind:    :system,
            payload: { "html" => true, "body" => body }
          } ])
        end

        private

        # Extract the title arg: everything after "import" in the raw string,
        # or from args[1..] if args are parsed.
        def import_title
          if invocation.args.size >= 2
            invocation.args[1..].join(" ").strip
          else
            # Fall back to parsing from raw: "/games import <title>"
            invocation.raw.to_s.strip.sub(%r{\A/games\s+import\s*}i, "").strip
          end
        end

        def open_import_sidebar
          title = import_title
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                sidebar_open:    "games_import",
                prefill:         title,
                text:            I18n.t("pito.slash.games.import.opening")
              }
            }
          ])
        end

        def usage_hint
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    :system,
              payload: {
                text: Pito::Copy.render("pito.copy.games.import_usage")
              }
            }
          ])
        end
      end
    end
  end
end
