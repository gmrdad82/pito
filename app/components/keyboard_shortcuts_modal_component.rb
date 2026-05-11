class KeyboardShortcutsModalComponent < ViewComponent::Base
  # Help overlay opened by `?` (and the visible `[_]` link in the
  # footer chrome).
  #
  # Scope: page-level + global hotkeys ONLY. Navigation between pages
  # and bulk operations live behind the SPACE leader menu (see
  # `config/keybindings.yml` + `leader_menu_controller.js`); the
  # opening hint below points users there. We deliberately do NOT
  # advertise the leader's contents here — the leader menu documents
  # itself when opened.
  #
  # 2026-05-10 refresh: dropped the legacy `g d/g c/g v/g s/g e`
  # navigation rows (now leader-driven); replaced the `space` row
  # selection binding with `x` (matches the TUI's row-selection key
  # after SPACE was promoted to leader in both surfaces).
  Section = Struct.new(:title, :rows, keyword_init: true)
  Row = Struct.new(:keys, :description, keyword_init: true)

  LEADER_HINT =
    "Press SPACE for the leader menu " \
    "(navigation between pages and bulk operations).".freeze

  SECTIONS = [
    Section.new(
      title: "general",
      rows: [
        Row.new(keys: "?", description: "toggle this help"),
        Row.new(keys: "q", description: "back / close (Esc on web)"),
        Row.new(keys: "t", description: "toggle dark/light theme"),
        Row.new(keys: "/", description: "open search modal"),
        Row.new(keys: "i", description: "open igdb add-game modal"),
        Row.new(keys: "Esc", description: "close overlay / clear filter")
      ]
    ),
    Section.new(
      title: "list pages (channels / videos)",
      rows: [
        Row.new(keys: "j / k", description: "move highlight down / up"),
        Row.new(keys: "x", description: "toggle row selection"),
        Row.new(keys: "s", description: "toggle star on highlighted row"),
        Row.new(keys: "D", description: "delete selection (or current row)"),
        Row.new(keys: "Y", description: "sync selection (or current row)"),
        Row.new(keys: "f s", description: "filter: starred (toggle)")
      ]
    ),
    Section.new(
      title: "detail pages (channel / video)",
      rows: [
        Row.new(keys: "v", description: "view URL in browser"),
        Row.new(keys: "s", description: "toggle star"),
        Row.new(keys: "Y", description: "sync this record"),
        Row.new(keys: "D", description: "delete this record")
      ]
    ),
    Section.new(
      title: "confirmation prompts",
      rows: [
        Row.new(keys: "y", description: "confirm"),
        Row.new(keys: "Esc / any other key", description: "cancel")
      ]
    )
  ].freeze

  def sections
    SECTIONS
  end

  def leader_hint
    LEADER_HINT
  end
end
