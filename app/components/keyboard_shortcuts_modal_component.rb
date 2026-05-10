class KeyboardShortcutsModalComponent < ViewComponent::Base
  # Phase 7.5 — Step 04. Mirrors the `pito` CLI's help overlay
  # (`extras/cli/src/ui/help.rs`) per locked decision Q6 (strict mirror,
  # CLI is the source of truth). Sections, keys, and descriptions come
  # straight from `help.rs::render`. No web-only additions.
  #
  # Rendered once in the layout chrome; opened by `keyboard#openHelp`
  # in response to `?` keypress or a click on the visible `[?]` link.
  Section = Struct.new(:title, :rows, keyword_init: true)
  Row = Struct.new(:keys, :description, keyword_init: true)

  SECTIONS = [
    Section.new(
      title: "general",
      rows: [
        Row.new(keys: "?", description: "toggle this help"),
        Row.new(keys: "q", description: "back / close"),
        Row.new(keys: "t", description: "toggle dark/light theme"),
        Row.new(keys: "/", description: "open search modal"),
        Row.new(keys: "i", description: "open igdb add-game modal"),
        Row.new(keys: "Esc", description: "close overlay / clear filter / leave bulk")
      ]
    ),
    Section.new(
      title: "navigation",
      rows: [
        Row.new(keys: "g d", description: "go to dashboard"),
        Row.new(keys: "g c", description: "go to channels"),
        Row.new(keys: "g v", description: "go to videos"),
        Row.new(keys: "g s", description: "go to saved views"),
        Row.new(keys: "g e", description: "go to settings")
      ]
    ),
    Section.new(
      title: "list pages (channels / videos)",
      rows: [
        Row.new(keys: "j / k", description: "move highlight down / up"),
        Row.new(keys: "space", description: "toggle bulk select on row (bulk mode only)"),
        Row.new(keys: "b", description: "toggle bulk mode"),
        Row.new(keys: "s", description: "toggle star on highlighted row"),
        Row.new(keys: "D", description: "delete selection (or current row)"),
        Row.new(keys: "Y", description: "sync selection (or current row)"),
        Row.new(keys: "f s", description: "filter: starred (toggle)"),
        Row.new(keys: "f c", description: "filter: connected (toggle)")
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
end
