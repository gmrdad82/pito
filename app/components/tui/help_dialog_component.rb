module Tui
  # Beta 4 — Phase D9 (2026-05-22). TUI help dialog. Replaces the legacy
  # `Tui::HelpOverlayComponent` with a wrapper around the canonical
  # `Tui::DialogComponent` chrome.
  # Updated Phase 6 (2026-05-24): section_nav keys corrected to Space-prefixed
  # leader navigation; focusable_nav group added (j/k/Enter); sort group
  # entries (s/S) added to panel_nav.
  # Updated E3 (2026-05-25): added sync_pause group (Space p, pause-from-sync
  # + 3-state sync states); calendar group (mode toggle, filter chips, month
  # nav); notifications group (filter chips, mark-all-read); scramble_row_insert
  # entry added to insert mode group; TAB/Shift-TAB already present in panel_nav.
  #
  # Lists every top-level keybinding pito supports (global flat keys,
  # section nav, panel nav, focusable nav, sort, mode, session) in a
  # which-key-style two-column tree (key on the left, lowercase label on
  # the right, grouped by category).
  #
  # Opened via `?` (the `tui-help-dialog` Stimulus controller intercepts the
  # key at document level) and closed via `[Esc]` per the canonical dialog
  # chrome contract. Mounted in `app/views/layouts/application.html.erb`.
  #
  # Group + item labels resolve through `help.overlay.*` i18n keys (locked
  # 2026-05-20). The same locale surface will export to the Ratatui TUI
  # client when that lands.
  #
  # Key glyphs (TAB / Esc / Space / `?` / etc.) are inlined here per the
  # canonical casing locked in `config/locales/keybindings/en.yml#keys`
  # (TAB all caps, Esc / Space / Shift / Ctrl capitalized, letters lowercase,
  # `-` combo separator).
  class HelpDialogComponent < ViewComponent::Base
    DIALOG_ID = "tui-help-dialog".freeze

    GROUPS = [
      {
        group_key: "global",
        items: [
          { key: "?",     label_key: "open_help" },
          { key: ":",     label_key: "command_palette" },
          { key: "/",     label_key: "search" },
          { key: "Space", label_key: "leader_menu" }
        ]
      },
      {
        group_key: "section_nav",
        items: [
          { key: "Space h", label_key: "home" },
          { key: "Space v", label_key: "videos" },
          { key: "Space g", label_key: "games" }
        ]
      },
      {
        group_key: "panel_nav",
        items: [
          { key: "TAB",       label_key: "cycle_forward" },
          { key: "Shift-TAB", label_key: "cycle_backward" }
        ]
      },
      {
        group_key: "focusable_nav",
        items: [
          { key: "j",     label_key: "next_focusable" },
          { key: "k",     label_key: "prev_focusable" },
          { key: "Enter", label_key: "activate" }
        ]
      },
      {
        group_key: "sort",
        items: [
          { key: "s", label_key: "sort_next_column" },
          { key: "S", label_key: "sort_reverse" }
        ]
      },
      {
        group_key: "sync_pause",
        items: [
          { key: "Space s",   label_key: "toggle_master_sync" },
          { key: "Space p",   label_key: "toggle_panel_pause" },
          { key: "[ ] sync",  label_key: "sync_state_idle" },
          { key: "[x] sync",  label_key: "sync_state_active" },
          { key: "[-] sync",  label_key: "sync_state_paused" },
          { key: "[!] sync",  label_key: "sync_state_disconnected" }
        ]
      },
      {
        group_key: "calendar",
        items: [
          { key: ": set calendar mode", label_key: "set_mode" },
          { key: ": filter calendar",   label_key: "filter_category" },
          { key: ": previous month",    label_key: "prev_month" },
          { key: ": next month",        label_key: "next_month" },
          { key: ": go to today",       label_key: "today" }
        ]
      },
      {
        group_key: "notifications",
        items: [
          { key: ": mark all read",   label_key: "mark_all_read" },
          { key: ": filter channel",  label_key: "filter_channel" },
          { key: ": filter game",     label_key: "filter_game" },
          { key: ": filter system",   label_key: "filter_system" },
          { key: ": filter manual",   label_key: "filter_manual" }
        ]
      },
      {
        group_key: "mode",
        items: [
          { key: "i",     label_key: "enter_insert" },
          { key: "Esc",   label_key: "exit_insert" },
          { key: "Space", label_key: "toggle_checkbox_insert" },
          { key: "r",     label_key: "scramble_row_insert" }
        ]
      },
      {
        group_key: "session",
        items: [
          { key: "q Q", label_key: "logout" },
          { key: "Esc", label_key: "close_modal" }
        ]
      }
    ].freeze
  end
end
