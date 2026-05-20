module Tui
  # Beta 4 — Phase F1. TUI help overlay. A `<dialog>`-backed modal that
  # lists every top-level keybinding pito supports (global flat keys,
  # section nav under SPACE, panel nav, session) in a which-key-style
  # two-column tree (key on the left, lowercase description on the
  # right, grouped by category).
  #
  # The groups are intentionally inlined as a static constant rather
  # than parsed from `config/keybindings.yml` — the YAML schema groups
  # bindings by page (page_actions / modal_actions / leader-menu
  # categories) which doesn't map cleanly onto the user-facing
  # categories rendered here (global / section nav / panel nav /
  # session). When YAML and overlay drift, the overlay is the surface
  # the user sees, so it stays the source of truth for THIS view.
  #
  # The overlay is opened via the `?` flat-key (handled by the
  # `tui-help-overlay` Stimulus controller — see
  # `app/javascript/controllers/tui_help_overlay_controller.js`) and
  # closed via Esc or another `?` press. Esc is the convention used
  # across every other modal in the app; `?` toggles the overlay
  # specifically so a second `?` from a help-induced workflow flips the
  # surface off without a hand jump to Esc.
  #
  # Key labels in the GROUPS constant follow the canonical casing
  # locked 2026-05-20 (see `config/locales/keybindings/en.yml#keys`):
  # `TAB` (acronym, all caps), `Esc` / `Space` / `Enter` / `Shift` /
  # `Ctrl` (capitalized), letter keys lowercase. Combos use `-` as
  # the separator (`Shift-TAB`, `Ctrl-h`).
  #
  # FB-71 (2026-05-20) — group titles and item labels are now
  # i18n-driven. GROUPS carries i18n key fragments (`group_key:` /
  # `label_key:`) instead of inline English copy; the ERB resolves them
  # through `t("help.overlay.groups.<group_key>.title")` and
  # `t("help.overlay.groups.<group_key>.items.<label_key>")` at render
  # time. The canonical copy lives in
  # `config/locales/help/en.yml` under `help.overlay.groups.*`.
  #
  # Mounted in `app/views/layouts/application.html.erb` near the end of
  # `<body>`, before the other modal mounts so the document order
  # mirrors usage frequency (help is the first surface a new user
  # opens).
  class HelpOverlayComponent < ViewComponent::Base
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
          { key: "g C", label_key: "calendar" },
          { key: "g c", label_key: "channels" },
          { key: "g v", label_key: "videos" },
          { key: "g p", label_key: "projects" },
          { key: "g g", label_key: "games" },
          { key: "g n", label_key: "notifications" },
          { key: "g s", label_key: "settings" }
        ]
      },
      {
        group_key: "panel_nav",
        items: [
          { key: "TAB",       label_key: "cycle_forward" },
          { key: "Shift-TAB", label_key: "cycle_backward" },
          { key: "Ctrl-h",    label_key: "panel_left" },
          { key: "Ctrl-l",    label_key: "panel_right" },
          { key: "Ctrl-k",    label_key: "panel_up" },
          { key: "Ctrl-j",    label_key: "panel_down" }
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
