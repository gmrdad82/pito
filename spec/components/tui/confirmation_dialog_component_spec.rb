require "rails_helper"

# FB-124 (2026-05-21). Locks the rendered DOM contract for the canonical
# `Tui::ConfirmationDialogComponent` — the dialog now used by the sessions
# bulk-revoke flow and (incrementally) every other destructive
# confirmation surface in the app.
#
# What this spec locks (drift in any of these silently changes the
# user-facing confirmation pattern):
#
#   * the `<dialog>` root carries the supplied `id` plus the
#     `.tui-confirmation-dialog` + `.tui-dialog-frame` class pair (the
#     shared frame chrome is required for the V4 corner-flush title +
#     `[Esc]` hint placement).
#   * the `title` paints left-flush on the top border via
#     `.tui-dialog-frame__title-left`.
#   * the `[Esc] to close` hint paints right-flush on the top border via
#     `.tui-dialog-frame__title-right`.
#   * the body renders ONE `<p>` carrying the supplied `message`.
#   * the action submit lives inside a `<form>` posting to
#     `action_path` and renders the bracketed `[<label>]` text.
#   * there is NO `[cancel]` action — `[Esc]` is the canonical dismiss.
#   * the `tui-confirmation-dialog` Stimulus controller is wired on the
#     root so the universal Esc + backdrop-no-dismiss behavior applies.
RSpec.describe Tui::ConfirmationDialogComponent, type: :component do
  let(:default_args) do
    {
      id: "test-dialog",
      title: "revoke",
      message: "revoke 1 session?",
      action_label: "revoke",
      action_path: "/sessions/revoke/1"
    }
  end

  it "renders with dialog id" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css("dialog#test-dialog.tui-confirmation-dialog.tui-dialog-frame")
  end

  it "renders title on top border" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css(".tui-dialog-frame__title-left", text: "revoke")
  end

  it "renders Esc hint on top-right border" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css(".tui-dialog-frame__title-right", text: /Esc.*close/)
  end

  it "renders the message" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css(".tui-confirmation-dialog__message", text: "revoke 1 session?")
  end

  it "renders the action submit inside a form" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css("form[action='/sessions/revoke/1']")
    expect(page).to have_text("[revoke]")
  end

  it "does NOT render a [cancel] button" do
    render_inline(described_class.new(**default_args))
    expect(page).not_to have_text("[cancel]")
  end

  it "wires the tui-confirmation-dialog Stimulus controller" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css("dialog[data-controller='tui-confirmation-dialog']")
  end

  it "renders the action as a danger-colored bracketed submit by default" do
    render_inline(described_class.new(**default_args))
    expect(page).to have_css("button.bracketed.text-danger[type='submit']")
  end

  it "supports a non-danger action variant (no .text-danger)" do
    render_inline(described_class.new(**default_args.merge(action_variant: :neutral)))
    expect(page).to have_css("button.bracketed[type='submit']")
    expect(page).not_to have_css("button.bracketed.text-danger[type='submit']")
  end

  it "honors a custom action_method (e.g. :post for the revoke flow)" do
    render_inline(described_class.new(**default_args.merge(action_method: :post)))
    # Rails serializes non-GET/POST verbs via a hidden `_method` field;
    # explicit :post leaves only the bare POST form with no override.
    expect(page).to have_css("form[method='post']")
    expect(page).not_to have_css("input[name='_method']")
  end
end
