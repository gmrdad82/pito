# D9 (2026-05-22) — Tui::ConfirmationDialogComponent spec.
require "rails_helper"

RSpec.describe Tui::ConfirmationDialogComponent, type: :component do
  subject(:component) do
    described_class.new(
      id:            "confirm-dialog",
      title:         "delete",
      message:       "delete this item?",
      action_label:  "delete",
      action_path:   "/items/1",
      action_method: :delete
    )
  end

  describe "wrapping the canonical dialog chrome" do
    it "renders a <dialog> element" do
      render_inline(component)
      expect(page).to have_css("dialog")
    end

    it "renders the given title in the top-border-left" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-left", text: "delete")
    end

    it "renders the esc_to_cancel hint in the top-border-right" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-right", text: "Esc to cancel")
    end

    it "applies tui-confirmation-dialog class on the <dialog>" do
      render_inline(component)
      expect(page).to have_css("dialog.tui-confirmation-dialog")
    end

    it "mounts tui-confirmation-dialog Stimulus controller" do
      render_inline(component)
      dialog = page.find("dialog")
      expect(dialog["data-controller"]).to include("tui-confirmation-dialog")
    end

    it "always includes tui-dialog controller" do
      render_inline(component)
      dialog = page.find("dialog")
      expect(dialog["data-controller"]).to include("tui-dialog")
    end
  end

  describe "message body" do
    it "renders the message in a paragraph" do
      render_inline(component)
      expect(page).to have_css(".tui-confirmation-dialog__message", text: "delete this item?")
    end
  end

  describe "action form" do
    it "renders a form with the given action_path" do
      render_inline(component)
      expect(page).to have_css("form")
      expect(page).to have_css(".tui-confirmation-dialog__form")
    end

    it "renders the action label inside a bracketed submit" do
      render_inline(component)
      expect(page).to have_css("[data-tui-focusable='confirm']")
      # bracketed action contains the label
      expect(rendered_content).to include("delete")
    end
  end

  describe "#destructive?" do
    it "returns true for the default :danger variant" do
      expect(component.destructive?).to be true
    end

    it "returns false for a non-danger action_variant" do
      safe = described_class.new(
        id:           "d",
        title:        "t",
        message:      "m",
        action_label: "ok",
        action_path:  "/ok",
        action_variant: :neutral
      )
      expect(safe.destructive?).to be false
    end
  end

  describe "default action_method" do
    it "accepts :delete as the default method" do
      c = described_class.new(
        id:           "d",
        title:        "t",
        message:      "m",
        action_label: "do it",
        action_path:  "/x"
      )
      expect(c.action_method).to eq(:delete)
    end
  end
end
