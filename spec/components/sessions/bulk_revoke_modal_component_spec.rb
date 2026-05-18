require "rails_helper"

# 2026-05-18 — Beta-3 lane B candidate B8.
#
# Sessions::BulkRevokeModalComponent owns the in-page confirm modal
# the bulk-revoke flow opens via the `sessions-bulk-revoke` Stimulus
# controller. Extracted from `_security_pane.html.erb` (the
# `<dialog id="revoke_sessions_modal">` block). The page-level
# `data-controller="sessions-bulk-revoke"` Stimulus mount lives on
# the parent `<fieldset>` in `_security_pane.html.erb`; this
# component is a child INSIDE that fieldset and owns ONLY the modal
# markup + targets + placeholder URL.
RSpec.describe Sessions::BulkRevokeModalComponent, type: :component do
  before { render_inline(described_class.new) }

  describe "dialog root" do
    it "renders a <dialog> with the expected id" do
      expect(page).to have_css("dialog#revoke_sessions_modal", visible: :all)
    end

    it "wires the confirm-modal controller for Esc / outside-click close" do
      expect(page).to have_css(
        "dialog#revoke_sessions_modal[data-controller='confirm-modal']",
        visible: :all
      )
      expect(page).to have_css(
        "dialog#revoke_sessions_modal[data-action*='click->confirm-modal#clickOutside']",
        visible: :all
      )
      expect(page).to have_css(
        "dialog#revoke_sessions_modal[data-action*='keydown->confirm-modal#keydown']",
        visible: :all
      )
    end
  end

  describe "form action URL — catalog-flagged invariant" do
    it "carries the literal `0` ids segment (not `1`, not blank)" do
      # The route constraint `[0-9,]+` requires a digit, and `0` is
      # filtered server-side by `parse_ids`. Stimulus rewrites the
      # segment to real ids at click time.
      form = page.find("form[data-sessions-bulk-revoke-target='modalForm']", visible: :all)
      expect(form[:action]).to end_with("/settings/sessions/revokes/0")
    end

    it "submits via POST" do
      form = page.find("form[data-sessions-bulk-revoke-target='modalForm']", visible: :all)
      # Rails form_with always emits POST at the form level; the
      # method override (if any) rides in a hidden `_method` field.
      expect(form[:method].to_s.downcase).to eq("post")
    end

    it "wires the CSRF refresh action on submit" do
      expect(page).to have_css(
        "form[data-sessions-bulk-revoke-target='modalForm'][data-action='submit->sessions-bulk-revoke#refreshCsrf']",
        visible: :all
      )
    end

    it "carries the hidden `confirm=yes` field BulkRevokesController gates on" do
      expect(page).to have_css(
        "form[data-sessions-bulk-revoke-target='modalForm'] input[type='hidden'][name='confirm'][value='yes']",
        visible: :all
      )
    end
  end

  describe "Stimulus targets" do
    it "renders the `modal` target on the dialog" do
      expect(page).to have_css("[data-sessions-bulk-revoke-target='modal']", visible: :all)
    end

    it "renders the `modalTitle` target" do
      expect(page).to have_css("[data-sessions-bulk-revoke-target='modalTitle']", visible: :all)
    end

    it "renders the `modalWarning` target (hidden by default)" do
      warning = page.find("[data-sessions-bulk-revoke-target='modalWarning']", visible: :all)
      expect(warning).not_to be_nil
      # The warning starts hidden — Stimulus reveals it when the
      # selected set includes the current session.
      expect(warning[:hidden]).to be_truthy
    end

    it "renders the `modalForm` target" do
      expect(page).to have_css("form[data-sessions-bulk-revoke-target='modalForm']", visible: :all)
    end
  end

  describe "action buttons" do
    it "renders a destructive [revoke] submit button" do
      expect(page).to have_css(
        "form[data-sessions-bulk-revoke-target='modalForm'] button[type='submit'].bracketed.text-danger",
        text: "[revoke]", visible: :all
      )
    end

    it "renders a [cancel] button wired to confirm-modal#close" do
      expect(page).to have_css(
        "button[type='button'].bracketed[data-action='confirm-modal#close']",
        text: "[cancel]", visible: :all
      )
    end
  end
end
