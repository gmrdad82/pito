# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlK::SectionComponent do
  let(:title_key) { "pito.palette.ctrl_k.sections.youtube" }
  let(:item_with_shortcut) do
    { label_key: "pito.palette.ctrl_k.commands.login", insert: "/login <code>", shortcut: "ctrl+a" }
  end
  let(:item_without_shortcut) do
    { label_key: "pito.palette.ctrl_k.commands.logout", insert: "/logout" }
  end

  describe "section title" do
    it "renders the translated title" do
      node = render_inline(described_class.new(title_key:, items: []))
      expect(node.text).to include(I18n.t(title_key))
    end

    it "exposes section Stimulus target" do
      node = render_inline(described_class.new(title_key:, items: []))
      expect(node.css("[data-pito--command-palette-target='section']")).not_to be_empty
    end
  end

  describe "item rendering" do
    let(:node) do
      render_inline(described_class.new(title_key:, items: [ item_with_shortcut, item_without_shortcut ]))
    end

    it "renders all item labels via i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.login"))
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.logout"))
    end

    it "renders the insert command on the right" do
      expect(node.text).to include("/login <code>")
      expect(node.text).to include("/logout")
    end

    it "always renders two spans per item (label + insert)" do
      node.css("[data-pito--command-palette-target='item']").each do |item|
        expect(item.css("span").length).to eq(2)
      end
    end

    it "sets data-insert on each item" do
      items = node.css("[data-pito--command-palette-target='item']")
      expect(items[0]["data-insert"]).to eq("/login <code>")
      expect(items[1]["data-insert"]).to eq("/logout")
    end

    it "sets data-label (lowercased) on each item for fuzzy search" do
      items = node.css("[data-pito--command-palette-target='item']")
      items.each do |item|
        expect(item["data-label"]).to be_present
        expect(item["data-label"]).to eq(item["data-label"].downcase)
      end
    end

    it "has no inline background/color styles (selection is CSS class only)" do
      node.css("*").each do |el|
        next if el["style"].blank?
        expect(el["style"]).not_to match(/background|color/i),
          "Unexpected inline style on #{el.name}: #{el['style']}"
      end
    end
  end
end
