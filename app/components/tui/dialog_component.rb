module Tui
  # Beta 4 — Phase D9 (2026-05-22). Canonical dialog chrome primitive.
  #
  # Single source of truth for the `.tui-dialog-frame` shell used by every
  # dialog in pito: ConfirmationDialog, HelpDialog, AboutDialog,
  # webhook help dialog, etc. The chrome renders:
  #
  #   * a `<dialog>` element with `border-radius: 0`, hairline border, and
  #     screen-accent border color when `[open]`
  #   * the dialog `title` left-flush ON the top border, sitting in a
  #     `background: var(--color-bg)` bg-cut span that VISUALLY breaks the
  #     border line behind the title text (FB-65 V4 chrome)
  #   * a `[Esc] to close` right-flush hint on the top border (mirror layout)
  #   * the dialog body via the `content` slot
  #
  # Consumers wrap their body markup inside `render Tui::DialogComponent.new(...)`
  # blocks; the chrome is identical across every dialog, so a single edit
  # here flows to all of them.
  #
  # Kwargs:
  #   id:             — DOM id for the dialog (consumers / keybindings target
  #                     this id via showModal()). Required.
  #   title:          — left-border title (lowercase per design.md). Required.
  #   screen_accent:  — Symbol section accent (`:home` / `:videos` / `:games`);
  #                     defaults to `:home`. Border + title color follow this
  #                     accent when the dialog is open.
  #   esc_hint_key:   — i18n key for the right-border dismiss hint. Defaults
  #                     to `tui.dialog.esc_to_close` ("Esc to close").
  #                     ConfirmationDialog flavor passes `tui.dialog.esc_to_cancel`.
  #   extra_classes:  — String of additional CSS classes applied to the
  #                     `<dialog>` element (e.g. consumer-specific selectors
  #                     so existing per-flavor CSS keeps working). Optional.
  #   extra_controllers: — Space-separated string of additional Stimulus
  #                     controllers to mount alongside `tui-dialog`. Optional.
  #
  # The `tui-dialog` Stimulus controller is ALWAYS mounted, providing:
  #
  #   * backdrop-click guard (cancel event preventDefault on backdrop click)
  #   * `[Esc]` is the canonical dismiss path
  #   * `open()` / `close()` actions for callers that drive the dialog from JS
  class DialogComponent < ViewComponent::Base
    renders_one :body
    renders_one :footer

    def initialize(id:, title:, screen_accent: :home, esc_hint_key: "tui.dialog.esc_to_close", extra_classes: nil, extra_controllers: nil)
      @id = id
      @title = title
      @screen_accent = screen_accent
      @esc_hint_key = esc_hint_key
      @extra_classes = extra_classes
      @extra_controllers = extra_controllers
    end

    attr_reader :id, :title, :screen_accent, :esc_hint_key, :extra_classes, :extra_controllers

    def dialog_classes
      base = "tui-dialog tui-dialog-frame"
      [ base, extra_classes ].compact.join(" ")
    end

    def dialog_controllers
      [ "tui-dialog", extra_controllers ].compact.join(" ")
    end

    def esc_hint_text
      I18n.t(esc_hint_key)
    end
  end
end
