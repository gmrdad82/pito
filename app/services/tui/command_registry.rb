module Tui
  # FB-170 (2026-05-21) — V6 command palette command registry.
  # FB-180 (2026-05-21) — name + hint flow through I18n
  # (`tui.commands.<key>.name` / `.hint`) so brand capitalization
  # (Meilisearch, Voyage AI, Slack, Discord, YouTube, …) is enforced
  # by the locale file rather than scattered string literals. See
  # `config/locales/tui/en.yml`.
  #
  # Centralized catalog of `:command` palette commands. Merges
  # screen-scoped commands (resolved from the current controller name)
  # with the always-available GLOBAL_COMMANDS set, in that order.
  #
  # Command shape — every command hash carries these keys:
  #   name:   String — user-typed verb (lowercase, may contain spaces).
  #   hint:   String — short description rendered to the right of the
  #           suggestion list.
  #   path:   Proc / nil — lambda returning a URL to navigate to when
  #           Enter runs the command. Wrapped as a Proc so we can call
  #           `Rails.application.routes.url_helpers.*_path` lazily; if
  #           routes aren't loaded yet (boot edge cases) the resolution
  #           still defers safely.
  #   method: Symbol / nil — HTTP method to use for `path` navigation
  #           (default :get; :post / :delete / :patch all supported via
  #           Turbo `data-turbo-method`).
  #   action: Symbol / nil — alternative to `path`; semantic action the
  #           Stimulus controller handles natively (e.g., :open_help,
  #           :open_about, :click, :clear_input).
  #   target: String / nil — CSS selector consumed by `action: :click`
  #           or `action: :clear_input`.
  #
  # Per-screen commands live in `Tui::ScreenCommands::<Screen>` modules
  # under `app/services/tui/screen_commands/`. Adding a new screen's
  # commands is a single-file change: drop a module with a
  # `.commands(context = {})` class method.
  class CommandRegistry
    GLOBAL_COMMANDS = [
      { name: I18n.t("tui.commands.home.name"),   hint: I18n.t("tui.commands.home.hint"),   path: -> { "/" } },
      { name: I18n.t("tui.commands.videos.name"), hint: I18n.t("tui.commands.videos.hint"), path: -> { "/videos" } },
      { name: I18n.t("tui.commands.games.name"),  hint: I18n.t("tui.commands.games.hint"),  path: -> { "/games" } },
      { name: I18n.t("tui.commands.help.name"),   hint: I18n.t("tui.commands.help.hint"),   action: :open_help },
      { name: I18n.t("tui.commands.about.name"),  hint: I18n.t("tui.commands.about.hint"),  action: :open_about },
      { name: I18n.t("tui.commands.logout.name"), hint: I18n.t("tui.commands.logout.hint"), method: :delete, path: -> { "/session" } }
    ].freeze

    # Lookup table — screen name (controller_name in Rails) -> module
    # constant. Add per-screen modules here as they ship.
    SCREEN_MODULES = {}.freeze

    class << self
      def commands_for(screen_name, context = {})
        screen = screen_name.to_s
        screen_commands = resolve_screen_module(screen)&.commands(context) || []
        # Screen-scoped commands first (more contextual / actionable),
        # then GLOBAL_COMMANDS so navigation verbs are always available
        # at the bottom of the list.
        screen_commands + GLOBAL_COMMANDS
      end

      private

      def resolve_screen_module(screen)
        const_name = SCREEN_MODULES[screen]
        return nil if const_name.nil?
        const_name.safe_constantize
      end
    end
  end
end
