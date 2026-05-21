module Pito
  # Pito::SecurityPanelComponent
  #
  # The security panel on Home (/). Shows the sessions table + TOTP status.
  # Extracted from `app/views/settings/_security_pane.html.erb`.
  #
  # ## Kwargs
  #
  # @param sessions [ActiveRecord::Relation<Session>] user's active sessions
  # @param sessions_sort [String] column name to sort by (device|browser|ip|last_seen|created)
  # @param sessions_dir [String] "asc" or "desc"
  #
  # ## Cable channel
  #
  # `pito:home:security` — broadcasts session changes (revoke, login, etc.)
  #
  # ## Focusables
  #
  # ordered list:
  # - `select_all` (style: :row) — bulk-revoke select-all toggle
  # - `row_<id>` (style: :row) — each session row
  #
  # ## Keybinds (panel-local)
  #
  # - Space (INSERT mode) — toggle focused row's checkbox
  # - r — bulk revoke
  #
  # ## Composes
  #
  # - `Sessions::TableComponent` (the sessions table)
  # - `Tui::ConfirmationDialogComponent` (bulk-revoke confirm dialog)
  class SecurityPanelComponent < ViewComponent::Base
    CABLE_CHANNEL = "pito:home:security".freeze

    def initialize(sessions:, sessions_sort:, sessions_dir:)
      @sessions = sessions
      @sessions_sort = sessions_sort
      @sessions_dir = sessions_dir
    end

    attr_reader :sessions, :sessions_sort, :sessions_dir

    def focusables
      [ { key: "select_all", style: :row } ] +
        sessions.map { |s| { key: "row_#{s.id}", style: :row } }
    end

    def keybinds
      {
        space_insert: I18n.t("pito.security.keybinds.toggle_checkbox", default: "toggle"),
        r: I18n.t("pito.security.keybinds.bulk_revoke", default: "bulk revoke")
      }
    end
  end
end
