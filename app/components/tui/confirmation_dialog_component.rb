module Tui
  # FB-124 (2026-05-21). Canonical confirmation dialog primitive.
  #
  # Built on the `.tui-dialog-frame` chrome (V4 title-in-border) shared by
  # the help overlay, About dialog, and webhook help dialog. The frame
  # carries:
  #
  #   * `title` left-flush in the top border (e.g. `revoke`, `delete`)
  #   * `[Esc] to close` right-flush in the top border (canonical dismiss)
  #   * a single body `<p>` message (e.g. `revoke 9 sessions?`)
  #   * one action submit (bracketed, danger-coloured by default)
  #
  # There is intentionally NO `[cancel]` button — `[Esc]` in the top-right
  # corner is the canonical dismiss. Backdrop clicks do NOT dismiss (FB-127
  # universal rule); the Stimulus controller swallows them.
  #
  # No internal hairlines / separators — the contract trades decoration
  # for Excel-density spacing.
  #
  # `action_variant` is reserved for future palette variations; the only
  # supported value today is `:danger` (default), which paints the submit
  # in `--color-danger` via `BracketedLinkComponent` with `destructive:
  # true`. Any non-`:danger` value renders the neutral bracketed surface.
  class ConfirmationDialogComponent < ViewComponent::Base
    def initialize(id:, title:, message:, action_label:, action_path:, action_method: :delete, action_variant: :danger)
      @id = id
      @title = title
      @message = message
      @action_label = action_label
      @action_path = action_path
      @action_method = action_method
      @action_variant = action_variant
    end

    attr_reader :id, :title, :message, :action_label, :action_path, :action_method, :action_variant

    def destructive?
      @action_variant == :danger
    end
  end
end
