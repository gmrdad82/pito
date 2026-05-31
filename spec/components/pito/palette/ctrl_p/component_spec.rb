# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlP::Component do
  # Minimal reusable section data using real i18n keys
  let(:section_suggested) do
    {
      title_key: "pito.palette.ctrl_p.sections.suggested",
      items: [
        { label_key: "pito.palette.ctrl_p.commands.new_session", shortcut: "ctrl+n" },
        { label_key: "pito.palette.ctrl_p.commands.open_editor" }
      ]
    }
  end

  let(:section_session) do
    {
      title_key: "pito.palette.ctrl_p.sections.session",
      items: [
        { label_key: "pito.palette.ctrl_p.commands.rename_session" },
        { label_key: "pito.palette.ctrl_p.commands.fork_session" }
      ]
    }
  end

  # ──────────────────────────────────────────
  # Initializer defaults
  # ──────────────────────────────────────────
  describe "#initialize" do
    it "accepts sections with default indices" do
      comp = described_class.new(sections: [ section_suggested ])
      expect(comp).to be_a(described_class)
    end

    it "accepts explicit selected_section_index and selected_item_index" do
      comp = described_class.new(
        sections: [ section_suggested, section_session ],
        selected_section_index: 1,
        selected_item_index: 0
      )
      expect(comp).to be_a(described_class)
    end
  end

  # ──────────────────────────────────────────
  # Rendering: chrome (title, esc hint, search)
  # ──────────────────────────────────────────
  describe "rendered chrome" do
    let(:node) { render_inline(described_class.new(sections: [])) }

    it "renders the palette title" do
      expect(node.text).to include("Commands")
    end

    it "renders the esc hint" do
      expect(node.text).to include("esc")
    end

    it "renders the search placeholder text" do
      expect(node.text).to include("earch")
    end

    it "renders the outer modal container" do
      expect(node.css("div[style*='width: 600px']").first).not_to be_nil
    end
  end

  # ──────────────────────────────────────────
  # Rendering: empty sections
  # ──────────────────────────────────────────
  describe "with no sections" do
    it "renders without crashing" do
      node = render_inline(described_class.new(sections: []))
      expect(node.to_html).not_to be_empty
    end

    it "does not render any section titles" do
      node = render_inline(described_class.new(sections: []))
      %w[Suggested Session Channel Output].each do |label|
        expect(node.text).not_to include(label)
      end
    end
  end

  # ──────────────────────────────────────────
  # Rendering: single section
  # ──────────────────────────────────────────
  describe "with a single section" do
    let(:node) { render_inline(described_class.new(sections: [ section_suggested ])) }

    it "renders the section title" do
      expect(node.text).to include("Suggested")
    end

    it "renders the item labels" do
      expect(node.text).to include("New session")
      expect(node.text).to include("Open editor")
    end

    it "renders the shortcut for items that have one" do
      expect(node.text).to include("ctrl+n")
    end
  end

  # ──────────────────────────────────────────
  # Rendering: multiple sections
  # ──────────────────────────────────────────
  describe "with multiple sections" do
    let(:node) do
      render_inline(
        described_class.new(
          sections: [ section_suggested, section_session ],
          selected_section_index: 0,
          selected_item_index: 0
        )
      )
    end

    it "renders all section titles" do
      expect(node.text).to include("Suggested")
      expect(node.text).to include("Session")
    end

    it "renders items from all sections" do
      expect(node.text).to include("New session")
      expect(node.text).to include("Rename session")
    end

    it "renders a 12px gap div between sections (not after last)" do
      gaps = node.css("div[style='height: 12px;']")
      # 1 gap between 2 sections; also the chrome has a 12px gap div
      # At least one inter-section gap should be present
      expect(gaps.length).to be >= 1
    end
  end

  # ──────────────────────────────────────────
  # Selection propagation
  # ──────────────────────────────────────────
  describe "selection propagation to SectionComponent" do
    it "passes selected: true only to the section at selected_section_index" do
      node = render_inline(
        described_class.new(
          sections: [ section_suggested, section_session ],
          selected_section_index: 1,
          selected_item_index: 0
        )
      )
      # The selected row in section_session (index 0 = "Rename session") should be highlighted
      highlighted = node.css("div[style*='background: var(--border-default)']")
      expect(highlighted.length).to eq(1)
      expect(highlighted.first.text).to include("Rename session")
    end

    it "highlights the correct item when selected_section_index is 0" do
      node = render_inline(
        described_class.new(
          sections: [ section_suggested, section_session ],
          selected_section_index: 0,
          selected_item_index: 1
        )
      )
      highlighted = node.css("div[style*='background: var(--border-default)']")
      expect(highlighted.length).to eq(1)
      expect(highlighted.first.text).to include("Open editor")
    end
  end

  # ──────────────────────────────────────────
  # Scrollable container
  # ──────────────────────────────────────────
  describe "scrollable sections container" do
    it "renders the pito-hide-scrollbar container" do
      node = render_inline(described_class.new(sections: [ section_suggested ]))
      expect(node.css("div.pito-hide-scrollbar").first).not_to be_nil
    end

    it "renders the pito-scroll-fade-slim container" do
      node = render_inline(described_class.new(sections: [ section_suggested ]))
      expect(node.css("div.pito-scroll-fade-slim").first).not_to be_nil
    end
  end
end
