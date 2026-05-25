module Tui
  # Tui::CodeComponent — monospace command-line display with optional copy action.
  #
  # Purpose:
  #   Renders a terminal command string inside a `.code-block` bordered box.
  #   When `copyable: true`, an inline `[ copy ]` bracketed action is rendered
  #   next to the `<code>` text. The existing `clipboard-copy` Stimulus controller
  #   wires the button to the clipboard API (navigator.clipboard.writeText).
  #
  #   On unauthenticated surfaces (no `.toast-container` in DOM), the clipboard-copy
  #   controller falls back to briefly swapping the button's label to `copied_message`
  #   and reverting after 1.5 s.
  #
  # Kwargs:
  #   text:            — The command string to display. Required.
  #   copyable:        — Boolean. When true, renders a `[ copy ]` action wired to
  #                      the clipboard-copy Stimulus controller. Defaults to false.
  #   copied_message:  — String. The label flashed briefly after a successful copy
  #                      (inline fallback on unauthenticated surfaces; toast message
  #                      on authenticated surfaces). Only relevant when copyable: true.
  #                      Defaults to "copied!".
  #   copy_label:      — String. The visible label on the copy action. Defaults to
  #                      "copy".
  #
  # Variants: none.
  #
  # Focusables: the `[ copy ]` action is focusable via the j/k cursor model
  #   when the consumer panel exposes it in `focusables`.
  #
  # CSS: relies on the existing `.code-block` + `.code-block code` rules in
  #   application.css (defined at § Item 1 — Code-block). No new classes added.
  #
  # Related:
  #   app/javascript/controllers/clipboard_copy_controller.js
  #   Tui::ActionComponent — renders the [ copy ] action
  #   Pito::AuthDialogComponent — primary consumer
  class CodeComponent < ViewComponent::Base
    def initialize(text:, copyable: false, copied_message: "copied!", copy_label: "copy")
      @text           = text
      @copyable       = copyable
      @copied_message = copied_message
      @copy_label     = copy_label
    end

    attr_reader :text, :copied_message, :copy_label

    def copyable?
      @copyable
    end
  end
end
