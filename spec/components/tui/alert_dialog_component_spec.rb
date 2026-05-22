# D9 (2026-05-22) — Tui::AlertDialogComponent spec.
require "rails_helper"

RSpec.describe Tui::AlertDialogComponent, type: :component do
  describe "single-line message" do
    subject(:component) do
      described_class.new(id: "alert-dialog", title: "invalid input", message: "something went wrong")
    end

    it "renders a <dialog> element" do
      render_inline(component)
      expect(page).to have_css("dialog")
    end

    it "renders the title in the top-border-left" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-left", text: "invalid input")
    end

    it "renders the esc_to_close hint in the top-border-right" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-right", text: "Esc to close")
    end

    it "applies tui-alert-dialog class on the <dialog>" do
      render_inline(component)
      expect(page).to have_css("dialog.tui-alert-dialog")
    end

    it "mounts tui-alert-dialog Stimulus controller" do
      render_inline(component)
      expect(page.find("dialog")["data-controller"]).to include("tui-alert-dialog")
    end

    it "always includes tui-dialog controller" do
      render_inline(component)
      expect(page.find("dialog")["data-controller"]).to include("tui-dialog")
    end

    it "renders the message as a single .tui-alert-dialog__line paragraph" do
      render_inline(component)
      expect(page).to have_css(".tui-alert-dialog__line", count: 1)
      expect(page).to have_css(".tui-alert-dialog__line", text: "something went wrong")
    end
  end

  describe "multi-line message (array)" do
    subject(:component) do
      described_class.new(
        id:      "alert-dialog",
        title:   "oops",
        message: [ "line one", "line two", "line three" ]
      )
    end

    it "renders one .tui-alert-dialog__line per array element" do
      render_inline(component)
      expect(page).to have_css(".tui-alert-dialog__line", count: 3)
    end

    it "renders each line in order" do
      render_inline(component)
      lines = page.all(".tui-alert-dialog__line").map(&:text)
      expect(lines).to eq([ "line one", "line two", "line three" ])
    end
  end

  describe "#message_lines" do
    it "wraps a string message in an array" do
      c = described_class.new(id: "d", title: "t", message: "single")
      expect(c.message_lines).to eq([ "single" ])
    end

    it "returns an array message as-is" do
      c = described_class.new(id: "d", title: "t", message: [ "a", "b" ])
      expect(c.message_lines).to eq([ "a", "b" ])
    end
  end
end
