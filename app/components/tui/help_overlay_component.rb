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
  # closed via ESC or another `?` press. ESC is the convention used
  # across every other modal in the app; `?` toggles the overlay
  # specifically so a second `?` from a help-induced workflow flips the
  # surface off without a hand jump to ESC.
  #
  # Mounted in `app/views/layouts/application.html.erb` near the end of
  # `<body>`, before the other modal mounts so the document order
  # mirrors usage frequency (help is the first surface a new user
  # opens).
  class HelpOverlayComponent < ViewComponent::Base
    GROUPS = [
      {
        title: "global",
        items: [
          { key: "?",     label: "open this help" },
          { key: ":",     label: "command palette" },
          { key: "/",     label: "search" },
          { key: "SPACE", label: "leader menu" }
        ]
      },
      {
        title: "section nav",
        items: [
          { key: "g h", label: "home" },
          { key: "g C", label: "calendar" },
          { key: "g c", label: "channels" },
          { key: "g v", label: "videos" },
          { key: "g p", label: "projects" },
          { key: "g g", label: "games" },
          { key: "g n", label: "notifications" },
          { key: "g s", label: "settings" }
        ]
      },
      {
        title: "panel nav",
        items: [
          { key: "TAB",       label: "cycle panel forward" },
          { key: "Shift+TAB", label: "cycle panel backward" },
          { key: "Ctrl+h",    label: "panel left" },
          { key: "Ctrl+l",    label: "panel right" },
          { key: "Ctrl+k",    label: "panel up" },
          { key: "Ctrl+j",    label: "panel down" }
        ]
      },
      {
        title: "session",
        items: [
          { key: "q Q", label: "logout" },
          { key: "ESC", label: "close modal / cancel" }
        ]
      }
    ].freeze
  end
end
