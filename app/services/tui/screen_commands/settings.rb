module Tui
  module ScreenCommands
    # FB-170 (2026-05-21) — /settings screen-scoped commands for the
    # V6 `:command` palette. Reindex triggers, toggle shortcuts, webhook
    # clears, and session sort verbs.
    #
    # FB-178 (2026-05-21) — Reindex commands no longer POST directly.
    # The palette dispatches an `action: :click` on the existing
    # `[reindex]` Stimulus element (data-reindex-brand="…"), which fires
    # the canonical action-bus (`Pito.dispatchAction`) flow wired through
    # `Tui::ActionButtonComponent`. This routes through the SAME
    # `Tui::ConfirmationDialogComponent` users see when they click
    # `[reindex]` manually — single confirmation path, no parallel POST flow.
    #
    # FB-180 (2026-05-21) — name + hint flow through I18n
    # (`tui.commands.<key>.name` / `.hint`). Brand names (Meilisearch,
    # Voyage AI, Slack, Discord) live capitalized in
    # `config/locales/tui/en.yml`. See registry header for the contract.
    module Settings
      module_function

      def commands(_context = {})
        routes = Rails.application.routes.url_helpers
        [
          # Stack — reindex triggers. ADR 0018 (action bus) routes these
          # through `window.Pito.dispatchAction` via the `action_name`
          # key the palette controller detects. The bus reads the
          # canonical `Pito::ActionRegistry` entry (path, confirmation,
          # cable_panel) so the palette, the click button, the future
          # leader-menu binding, MCP, and CLI all share the same
          # confirmation surface and POST endpoint. No more parallel
          # `:click` simulation path.
          {
            name: I18n.t("tui.commands.reindex_meilisearch.name"),
            hint: I18n.t("tui.commands.reindex_meilisearch.hint"),
            action_name: :reindex_meilisearch
          },
          {
            name: I18n.t("tui.commands.reindex_voyage.name"),
            hint: I18n.t("tui.commands.reindex_voyage.hint"),
            action_name: :reindex_voyage
          },

          # Notifications — toggle the shared "all" + "daily digest"
          # checkboxes via JS click (the form submits async).
          {
            name: I18n.t("tui.commands.toggle_all.name"),
            hint: I18n.t("tui.commands.toggle_all.hint"),
            action: :click,
            target: "#notification-all-checkbox"
          },
          {
            name: I18n.t("tui.commands.toggle_daily.name"),
            hint: I18n.t("tui.commands.toggle_daily.hint"),
            action: :click,
            target: "#notification-daily-checkbox"
          },

          # Webhook URL clears — sets the input value to "" + dispatches
          # a change event so any wiring catches the empty value.
          {
            name: I18n.t("tui.commands.clear_discord.name"),
            hint: I18n.t("tui.commands.clear_discord.hint"),
            action: :clear_input,
            target: "#discord_url"
          },
          {
            name: I18n.t("tui.commands.clear_slack.name"),
            hint: I18n.t("tui.commands.clear_slack.hint"),
            action: :clear_input,
            target: "#slack_url"
          },

          # Sessions sort — every column, both directions. Drives the
          # `?sessions_sort=…&sessions_dir=…` query string on /settings
          # (canonical mechanism, see SettingsController).
          *sessions_sort_commands(routes)
        ]
      end

      def sessions_sort_commands(routes)
        # SESSIONS_ALLOWED_SORTS in SettingsController is the canonical
        # set; mirror it here as the palette-visible verbs. Each column
        # has matching i18n keys at
        # `tui.commands.sort_sessions_<column>_<dir>.name` / `.hint`.
        columns = %w[device browser ip last_seen created]
        columns.flat_map do |column|
          %w[asc desc].map do |dir|
            key = "tui.commands.sort_sessions_#{column}_#{dir}"
            {
              name: I18n.t("#{key}.name"),
              hint: I18n.t("#{key}.hint"),
              path: -> { routes.settings_path(sessions_sort: column, sessions_dir: dir) }
            }
          end
        end
      end
    end
  end
end
