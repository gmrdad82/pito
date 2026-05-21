require "rails_helper"

# FB-172 (2026-05-21). Locks the rendered DOM contract for the canonical
# `Tui::AlertDialogComponent` — a message-only sibling of
# `Tui::ConfirmationDialogComponent` used for non-decisional
# notifications such as the keyboard-only "invalid input" alert.
#
# What this spec locks:
#
#   * the `<dialog>` root carries the supplied `id` plus the
#     `.tui-alert-dialog` + `.tui-dialog-frame` class pair (the shared
#     frame chrome is required for the V4 corner-flush title + `[Esc]`
#     hint placement).
#   * the `title` paints left-flush on the top border via
#     `.tui-dialog-frame__title-left`.
#   * the `[Esc] to close` hint paints right-flush on the top border via
#     `.tui-dialog-frame__title-right`.
#   * `message:` accepts EITHER a single string OR an array; arrays
#     render one `.tui-alert-dialog__line` `<p>` per entry.
#   * there is NO `<form>` and NO submit button — this dialog has no
#     primary action; `[Esc]` is the ONLY dismiss path.
#   * the `tui-dialog-frame` + `tui-alert-dialog` Stimulus controllers
#     are wired on the root so backdrop-click-prevent + imperative
#     open/close behavior apply.
RSpec.describe Tui::AlertDialogComponent, type: :component do
  let(:default_args) do
    {
      id: "test-alert",
      title: "invalid input",
      message: "mouse interaction forbidden"
    }
  end

  it "renders dialog with title and message" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css("dialog#test-alert.tui-alert-dialog.tui-dialog-frame")
    expect(page).to have_css(".tui-dialog-frame__title-left", text: "invalid input")
    expect(page).to have_css(".tui-dialog-frame__title-right", text: /Esc.*close/)
    expect(page).to have_css(".tui-alert-dialog__line", text: "mouse interaction forbidden")
  end

  it "accepts an array of message lines" do
    render_inline(described_class.new(id: "x", title: "t", message: [ "line one", "line two" ]))
    lines = page.all(".tui-alert-dialog__line").map(&:text)
    expect(lines).to eq([ "line one", "line two" ])
  end

  it "does NOT have a submit action" do
    render_inline(described_class.new(**default_args))
    expect(page).not_to have_css("button[type='submit']")
    expect(page).not_to have_css("form")
  end

  it "wires both the tui-dialog-frame and tui-alert-dialog Stimulus controllers" do
    render_inline(described_class.new(**default_args))
    dialog = page.find("dialog#test-alert")
    controllers = dialog["data-controller"].to_s.split
    expect(controllers).to include("tui-dialog-frame", "tui-alert-dialog")
  end
end
