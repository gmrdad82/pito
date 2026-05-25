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
  # `pito:home:security` — derived via `cable_channel_for(PANEL_NAME)` from
  # the `Tui::PanelBase` mixin. Broadcasts session changes (revoke, login).
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
  #
  # ## Palette commands (`:` palette, panel_commands)
  #
  # sort sessions by device      — :sort_table  { table: "sessions", column: "device" }
  # sort sessions by browser     — :sort_table  { table: "sessions", column: "browser" }
  # sort sessions by IP          — :sort_table  { table: "sessions", column: "ip" }
  # sort sessions by last seen   — :sort_table  { table: "sessions", column: "last_seen" }
  # sort sessions by created at  — :sort_table  { table: "sessions", column: "created" }
  # select all sessions          — :click_focusable { focusable: "select_all" }
  # revoke all sessions beside this one — :revoke_all_except_current
  #
  # ## Scramble-transition new-row insertion
  #
  # `sessions-scramble` Stimulus controller mounts on the
  # `<turbo-frame id="sessions_panel">` inside `Sessions::TableComponent`.
  # On connect it walks up the DOM to the panel root (the element with
  # `data-tui-panel-cable-name-value`) and attaches a listener for the
  # `pito:panel:security:received` DOM event fired by `tui-panel-cable`.
  # On `kind: "session_created"`, it expects a Turbo Stream `append` to
  # have already inserted the new `<tr>` (wired server-side in C9), then
  # scrambles each data cell from random chars to final content over ~400 ms
  # (10 frames × 40 ms, vanilla setInterval — no external animation library).
  # Sort is reset to creation-descending on insertion so the new row is
  # immediately visible.
  #
  # ## Phase 2C (2026-05-23)
  #
  # Wired with the canonical `Tui::PanelBase` mixin. Cable channel is now
  # derived via `cable_channel_for(PANEL_NAME)` (canonical
  # `pito:<screen>:<panel>` grammar); the legacy `CABLE_CHANNEL` constant
  # is gone. Title resolves from `tui.home.panels.security.title` so the
  # future Ratatui client reads the same YAML.
  class SecurityPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :security

    def initialize(sessions:, sessions_sort:, sessions_dir:)
      @sessions = sessions
      @sessions_sort = sessions_sort
      @sessions_dir = sessions_dir
    end

    attr_reader :sessions, :sessions_sort, :sessions_dir

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

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

    # Phase 2C — feed only the key strings into panel_root_data. The
    # full hash list (with :style entries) is retained for legacy
    # consumers that still need per-element CSS styling.
    def focusable_keys
      focusables.map { |f| f.is_a?(Hash) ? f[:key] : f }
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusable_keys, keybinds: keybinds, panel_commands: panel_commands)
    end

    # Phase 1C (2026-05-24) — `:` palette commands for the security
    # panel. Sort verbs target the sessions table by column; `select all`
    # / `revoke selected` / `revoke all except this` map to the existing
    # bulk-revoke flow. The action_names below (select_all_sessions,
    # revoke_selected_sessions, revoke_all_except_current) are STUB
    # placeholders — they'll be wired into ActionRegistry once the bulk
    # actions get pulled out of the inline form into action-bus form
    # (Phase 2 work). The palette + JS still references them so the
    # plumbing surfaces today; the action lookup will warn until the
    # registry entries land. See `Pito::CommandPalette::Collector` for
    # the merge contract.
    def panel_commands
      [
        { key: "sort_sessions_device",
          name: I18n.t("tui.commands.sort_sessions_device.name"),
          hint: I18n.t("tui.commands.sort_sessions_device.hint"),
          action_name: :sort_table,
          args: { table: "sessions", column: "device" } },
        { key: "sort_sessions_browser",
          name: I18n.t("tui.commands.sort_sessions_browser.name"),
          hint: I18n.t("tui.commands.sort_sessions_browser.hint"),
          action_name: :sort_table,
          args: { table: "sessions", column: "browser" } },
        { key: "sort_sessions_ip",
          name: I18n.t("tui.commands.sort_sessions_ip.name"),
          hint: I18n.t("tui.commands.sort_sessions_ip.hint"),
          action_name: :sort_table,
          args: { table: "sessions", column: "ip" } },
        { key: "sort_sessions_last_seen",
          name: I18n.t("tui.commands.sort_sessions_last_seen.name"),
          hint: I18n.t("tui.commands.sort_sessions_last_seen.hint"),
          action_name: :sort_table,
          args: { table: "sessions", column: "last_seen" } },
        { key: "sort_sessions_created",
          name: I18n.t("tui.commands.sort_sessions_created.name"),
          hint: I18n.t("tui.commands.sort_sessions_created.hint"),
          action_name: :sort_table,
          args: { table: "sessions", column: "created" } },
        { key: "select_all_sessions",
          name: I18n.t("tui.commands.select_all_sessions.name"),
          hint: I18n.t("tui.commands.select_all_sessions.hint"),
          action_name: :click_focusable,
          args: { focusable: "select_all" } },
        { key: "revoke_all_except_current",
          name: I18n.t("tui.commands.revoke_all_except_current.name"),
          hint: I18n.t("tui.commands.revoke_all_except_current.hint"),
          action_name: :revoke_all_except_current },
        { key: "revoke_selected_sessions",
          name: I18n.t("tui.commands.revoke_selected_sessions.name"),
          hint: I18n.t("tui.commands.revoke_selected_sessions.hint"),
          action_name: :revoke_selected_sessions },
        { key: "sync_toggle_security",
          name: I18n.t("tui.commands.sync_toggle.name", label: "security"),
          hint: I18n.t("tui.commands.sync_toggle.hint", label: "security"),
          action_name: :sync_toggle,
          args: { target: "home.security" } }
      ]
    end
  end
end
