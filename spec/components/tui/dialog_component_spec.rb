# D9 (2026-05-22) — Canonical Tui::DialogComponent chrome contract.
require "rails_helper"

RSpec.describe Tui::DialogComponent, type: :component do
  subject(:component) { described_class.new(id: "test-dialog", title: "test title") }

  describe "rendering the <dialog> element" do
    it "renders a <dialog> element" do
      render_inline(component)
      expect(page).to have_css("dialog")
    end

    it "sets the given id on the <dialog> element" do
      render_inline(component)
      expect(page).to have_css("dialog#test-dialog")
    end

    it "applies tui-dialog and tui-dialog-frame classes" do
      render_inline(component)
      expect(page).to have_css("dialog.tui-dialog.tui-dialog-frame")
    end
  end

  describe "title in top-border-left" do
    it "renders a title span with the given title text" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-left", text: "test title")
    end
  end

  describe "Esc hint in top-border-right" do
    it "renders the default esc_to_close hint from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-right", text: "Esc to close")
    end

    it "uses a custom esc_hint_key when provided" do
      custom = described_class.new(id: "d", title: "t", esc_hint_key: "tui.dialog.esc_to_cancel")
      render_inline(custom)
      expect(page).to have_css(".tui-dialog-frame__title-right", text: "Esc to cancel")
    end
  end

  describe "data-controller" do
    it "always includes tui-dialog controller" do
      render_inline(component)
      dialog = page.find("dialog")
      expect(dialog["data-controller"]).to include("tui-dialog")
    end

    it "appends extra_controllers when provided" do
      c = described_class.new(id: "d", title: "t", extra_controllers: "my-controller")
      render_inline(c)
      dialog = page.find("dialog")
      expect(dialog["data-controller"]).to include("tui-dialog")
      expect(dialog["data-controller"]).to include("my-controller")
    end
  end

  describe "data-section (screen_accent)" do
    it "defaults data-section to home" do
      render_inline(component)
      expect(page.find("dialog")["data-section"]).to eq("home")
    end

    it "sets data-section to videos when screen_accent is :videos" do
      c = described_class.new(id: "d", title: "t", screen_accent: :videos)
      render_inline(c)
      expect(page.find("dialog")["data-section"]).to eq("videos")
    end

    it "sets data-section to games when screen_accent is :games" do
      c = described_class.new(id: "d", title: "t", screen_accent: :games)
      render_inline(c)
      expect(page.find("dialog")["data-section"]).to eq("games")
    end
  end

  describe "extra_classes" do
    it "appends extra_classes to the dialog element" do
      c = described_class.new(id: "d", title: "t", extra_classes: "my-special-dialog")
      render_inline(c)
      expect(page).to have_css("dialog.tui-dialog.tui-dialog-frame.my-special-dialog")
    end

    it "omits extra_classes when not provided" do
      render_inline(component)
      expect(page.find("dialog")["class"]).not_to include("nil")
    end
  end

  describe "content slot" do
    it "renders content passed as a block" do
      render_inline(component) { "<p class='slot-content'>body here</p>".html_safe }
      expect(page).to have_css("p.slot-content", text: "body here")
    end
  end

  describe "#dialog_classes helper" do
    it "includes tui-dialog and tui-dialog-frame" do
      expect(component.dialog_classes).to include("tui-dialog")
      expect(component.dialog_classes).to include("tui-dialog-frame")
    end

    it "appends extra_classes when present" do
      c = described_class.new(id: "d", title: "t", extra_classes: "extra")
      expect(c.dialog_classes).to include("extra")
    end
  end

  describe "#dialog_controllers helper" do
    it "always starts with tui-dialog" do
      expect(component.dialog_controllers).to start_with("tui-dialog")
    end

    it "appends extra_controllers when present" do
      c = described_class.new(id: "d", title: "t", extra_controllers: "foo-bar")
      expect(c.dialog_controllers).to include("foo-bar")
    end
  end
end
