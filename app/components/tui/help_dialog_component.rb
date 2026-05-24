module Tui
  # Beta 4 — Phase D9 (2026-05-22). TUI help dialog. Replaces the legacy
  # `Tui::HelpOverlayComponent` with a wrapper around the canonical
  # `Tui::DialogComponent` chrome.
  #
  # Lists every top-level keybinding pito supports (global flat keys,
  # section nav, panel nav, mode, session) in a which-key-style two-column
  # tree (key on the left, lowercase label on the right, grouped by
  # category).
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
          { key: "g h", label_key: "home" },
          { key: "g v", label_key: "videos" },
          { key: "g g", label_key: "games" }
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
        group_key: "mode",
        items: [
          { key: "i",     label_key: "enter_insert" },
          { key: "Esc",   label_key: "exit_insert" },
          { key: "Space", label_key: "toggle_checkbox_insert" }
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
