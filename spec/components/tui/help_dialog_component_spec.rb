# D9 (2026-05-22) — Tui::HelpDialogComponent spec.
require "rails_helper"

RSpec.describe Tui::HelpDialogComponent, type: :component do
  subject(:component) { described_class.new }

  describe "dialog chrome" do
    it "renders a <dialog> element" do
      render_inline(component)
      expect(page).to have_css("dialog")
    end

    it "uses DIALOG_ID as the element id" do
      render_inline(component)
      expect(page).to have_css("dialog##{described_class::DIALOG_ID}")
    end

    it "renders the i18n title 'help' in the top-border-left" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-left", text: "help")
    end

    it "renders the esc_to_close hint in the top-border-right" do
      render_inline(component)
      expect(page).to have_css(".tui-dialog-frame__title-right", text: "Esc to close")
    end

    it "applies the tui-help-dialog class" do
      render_inline(component)
      expect(page).to have_css("dialog.tui-help-dialog")
    end

    it "mounts the tui-help-dialog Stimulus controller" do
      render_inline(component)
      expect(page.find("dialog")["data-controller"]).to include("tui-help-dialog")
    end
  end

  describe "keybinding groups" do
    it "renders one section per group in GROUPS" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group",
                               count: described_class::GROUPS.length)
    end

    it "renders the 'global' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "global")
    end

    it "renders the 'section nav' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "section nav")
    end

    it "renders the 'panel nav' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "panel nav")
    end

    it "renders the 'focusable nav' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "focusable nav")
    end

    it "renders the 'sort' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "sort")
    end

    it "renders the 'mode' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "mode")
    end

    it "renders the 'session' group title from i18n" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__group-title", text: "session")
    end

    it "renders at least one .tui-help-dialog__key element" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__key")
    end

    it "renders at least one .tui-help-dialog__label element" do
      render_inline(component)
      expect(page).to have_css(".tui-help-dialog__label")
    end

    it "renders the ? key for open_help" do
      render_inline(component)
      keys = page.all(".tui-help-dialog__key").map(&:text)
      expect(keys).to include("?")
    end

    it "renders the 'open this help' label" do
      render_inline(component)
      labels = page.all(".tui-help-dialog__label").map(&:text)
      expect(labels).to include("open this help")
    end
  end

  describe "DIALOG_ID constant" do
    it "is tui-help-dialog" do
      expect(described_class::DIALOG_ID).to eq("tui-help-dialog")
    end
  end

  describe "GROUPS constant" do
    it "defines 7 groups" do
      expect(described_class::GROUPS.length).to eq(7)
    end

    it "has global as the first group" do
      expect(described_class::GROUPS.first[:group_key]).to eq("global")
    end

    it "has session as the last group" do
      expect(described_class::GROUPS.last[:group_key]).to eq("session")
    end

    it "includes a focusable_nav group" do
      keys = described_class::GROUPS.map { |g| g[:group_key] }
      expect(keys).to include("focusable_nav")
    end

    it "includes a sort group" do
      keys = described_class::GROUPS.map { |g| g[:group_key] }
      expect(keys).to include("sort")
    end

    it "section_nav items use Space-prefixed leader navigation" do
      section_nav = described_class::GROUPS.find { |g| g[:group_key] == "section_nav" }
      item_keys = section_nav[:items].map { |i| i[:key] }
      expect(item_keys).to contain_exactly("Space h", "Space v", "Space g")
    end

    it "focusable_nav group contains j, k, Enter" do
      focusable_nav = described_class::GROUPS.find { |g| g[:group_key] == "focusable_nav" }
      item_keys = focusable_nav[:items].map { |i| i[:key] }
      expect(item_keys).to contain_exactly("j", "k", "Enter")
    end

    it "sort group contains s and S" do
      sort = described_class::GROUPS.find { |g| g[:group_key] == "sort" }
      item_keys = sort[:items].map { |i| i[:key] }
      expect(item_keys).to contain_exactly("s", "S")
    end

    it "every group has a :group_key and :items array" do
      described_class::GROUPS.each do |group|
        expect(group).to have_key(:group_key)
        expect(group[:items]).to be_an(Array)
        expect(group[:items]).not_to be_empty
      end
    end
  end
end
