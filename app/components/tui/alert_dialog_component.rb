module Tui
  # FB-172 (2026-05-21). Message-only alert dialog primitive.
  #
  # Built on the `.tui-dialog-frame` chrome (V4 title-in-border) shared by
  # the confirmation dialog, help overlay, About dialog, and webhook help
  # dialog. The frame carries:
  #
  #   * `title` left-flush in the top border (e.g. `invalid input`)
  #   * `[Esc] to close` right-flush in the top border (canonical dismiss)
  #   * one or more body `<p>` lines (the alert message)
  #
  # Distinct from `Tui::ConfirmationDialogComponent` because there is no
  # primary action — the user can ONLY read and dismiss. No form, no
  # submit button. Used for non-decisional notifications such as the
  # keyboard-only mouse-interaction-forbidden alert (FB-172).
  #
  # `message:` accepts either a single string OR an array of strings; an
  # array renders one `<p>` per line so callers can stack a witty title
  # with a help-key affordance without resorting to inline `<br>` tags.
  #
  # Backdrop clicks DO NOT dismiss (FB-127 universal rule); the
  # `tui-dialog-frame` Stimulus controller swallows them at the capture
  # phase. `[Esc]` is the canonical dismiss path.
  class AlertDialogComponent < ViewComponent::Base
    def initialize(id:, title:, message:)
      @id = id
      @title = title
      @message = message
    end

    attr_reader :id, :title, :message

    def message_lines
      Array(@message)
    end
  end
end
