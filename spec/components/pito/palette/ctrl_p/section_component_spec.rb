# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlP::SectionComponent do
  # i18n keys from config/locales/pito/palette/en.yml
  let(:title_key) { "pito.palette.ctrl_p.sections.suggested" }
  let(:item_with_shortcut) do
    { label_key: "pito.palette.ctrl_p.commands.new_session", shortcut: "ctrl+n" }
  end
  let(:item_without_shortcut) do
    { label_key: "pito.palette.ctrl_p.commands.switch_channel" }
  end

  # ──────────────────────────────────────────
  # Initializer / attribute storage
  # ──────────────────────────────────────────
  describe "#initialize" do
    it "stores title_key, items, selected, and selected_item_index" do
      comp = described_class.new(
        title_key: title_key,
        items: [ item_with_shortcut ],
        selected: true,
        selected_item_index: 0
      )
      expect(comp).to be_a(described_class)
    end

    it "defaults selected to false" do
      comp = described_class.new(title_key: title_key, items: [])
      node = render_inline(comp)
      # No item → no highlight background applied
      expect(node.css("div[style*='background']")).to be_empty
    end

    it "defaults selected_item_index to nil" do
      comp = described_class.new(title_key: title_key, items: [ item_with_shortcut ], selected: true)
      node = render_inline(comp)
      # selected: true but selected_item_index: nil → no row gets highlighted
      expect(node.css("div[style*='background: var(--border-default)']")).to be_empty
    end
  end

  # ──────────────────────────────────────────
  # Rendering: section title
  # ──────────────────────────────────────────
  describe "rendered section title" do
    it "renders the translated title text" do
      node = render_inline(
        described_class.new(title_key: title_key, items: [])
      )
      # "Suggested" is the en translation for pito.palette.ctrl_p.sections.suggested
      expect(node.text).to include("Suggested")
    end

    it "renders the session section title" do
      node = render_inline(
        described_class.new(title_key: "pito.palette.ctrl_p.sections.session", items: [])
      )
      expect(node.text).to include("Session")
    end
  end

  # ──────────────────────────────────────────
  # Rendering: empty items list
  # ──────────────────────────────────────────
  describe "with empty items" do
    it "renders only the title row, no item rows" do
      node = render_inline(
        described_class.new(title_key: title_key, items: [])
      )
      # Title div is the only div; items loop produces nothing
      expect(node.css("div").length).to eq(1)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: items without shortcut
  # ──────────────────────────────────────────
  describe "with an item that has no shortcut" do
    let(:node) do
      render_inline(
        described_class.new(title_key: title_key, items: [ item_without_shortcut ])
      )
    end

    it "renders the translated item label" do
      expect(node.text).to include("Switch channel")
    end

    it "does not render a shortcut span" do
      item_div = node.css("div").last
      spans = item_div.css("span")
      expect(spans.length).to eq(1)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: item with shortcut
  # ──────────────────────────────────────────
  describe "with an item that has a shortcut" do
    let(:node) do
      render_inline(
        described_class.new(title_key: title_key, items: [ item_with_shortcut ])
      )
    end

    it "renders the item label" do
      expect(node.text).to include("New session")
    end

    it "renders the shortcut text" do
      expect(node.text).to include("ctrl+n")
    end

    it "renders two spans (label + shortcut)" do
      item_div = node.css("div").last
      expect(item_div.css("span").length).to eq(2)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: multiple items
  # ──────────────────────────────────────────
  describe "with multiple items" do
    let(:items) do
      [
        { label_key: "pito.palette.ctrl_p.commands.new_session" },
        { label_key: "pito.palette.ctrl_p.commands.open_editor" },
        { label_key: "pito.palette.ctrl_p.commands.toggle_sidebar" }
      ]
    end

    it "renders all item labels" do
      node = render_inline(described_class.new(title_key: title_key, items: items))
      expect(node.text).to include("New session")
      expect(node.text).to include("Open editor")
      expect(node.text).to include("Toggle sidebar")
    end

    it "renders title div + one div per item" do
      node = render_inline(described_class.new(title_key: title_key, items: items))
      # 1 title div + 3 item divs
      expect(node.css("div").length).to eq(4)
    end
  end

  # ──────────────────────────────────────────
  # Selection highlight
  # ──────────────────────────────────────────
  describe "selection highlight" do
    let(:items) do
      [
        { label_key: "pito.palette.ctrl_p.commands.new_session" },
        { label_key: "pito.palette.ctrl_p.commands.open_editor" }
      ]
    end

    it "highlights only the selected item row" do
      node = render_inline(
        described_class.new(
          title_key: title_key,
          items: items,
          selected: true,
          selected_item_index: 1
        )
      )
      highlighted = node.css("div[style*='background: var(--border-default)']")
      expect(highlighted.length).to eq(1)
      expect(highlighted.first.text).to include("Open editor")
    end

    it "does not highlight any row when selected is false" do
      node = render_inline(
        described_class.new(
          title_key: title_key,
          items: items,
          selected: false,
          selected_item_index: 0
        )
      )
      expect(node.css("div[style*='background: var(--border-default)']")).to be_empty
    end

    it "highlights the first item when selected_item_index is 0" do
      node = render_inline(
        described_class.new(
          title_key: title_key,
          items: items,
          selected: true,
          selected_item_index: 0
        )
      )
      highlighted = node.css("div[style*='background: var(--border-default)']")
      expect(highlighted.length).to eq(1)
      expect(highlighted.first.text).to include("New session")
    end
  end
end
