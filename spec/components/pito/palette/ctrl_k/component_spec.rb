# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlK::Component do
  let(:youtube_section) do
    {
      title_key: "pito.palette.ctrl_k.sections.youtube",
      items: [
        { label_key: "pito.palette.ctrl_k.commands.connect",    insert: "/connect" },
        { label_key: "pito.palette.ctrl_k.commands.disconnect", insert: "/disconnect <@handle>" }
      ]
    }
  end

  let(:general_section) do
    {
      title_key: "pito.palette.ctrl_k.sections.general",
      items: [
        { label_key: "pito.palette.ctrl_k.commands.help",        insert: "/help" },
        { label_key: "pito.palette.ctrl_k.commands.login", insert: "/login <code>" }
      ]
    }
  end

  # ── Chrome ─────────────────────────────────────────────────────────────────

  describe "chrome (title, esc hint, search)" do
    subject(:node) { render_inline(described_class.new(sections: [])) }

    it "renders the palette title from i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.title"))
    end

    it "renders the esc hint from i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.esc_hint"))
    end

    it "renders a real search input (not a fake cursor)" do
      expect(node.css("input[type='text']")).not_to be_empty
    end

    it "search input has the correct Stimulus data-action" do
      input = node.css("input[type='text']").first
      expect(input["data-action"]).to include("input->pito--command-palette#filter")
    end

    it "search input has the correct Stimulus target" do
      input = node.css("input[type='text']").first
      expect(input["data-pito--command-palette-target"]).to eq("search")
    end

    it "renders the 600px-wide modal container" do
      expect(node.css("div.w-\\[600px\\]")).not_to be_empty
    end

    it "has no inline color/background styles (CSS class for theming)" do
      node.css("*").each do |el|
        next if el["style"].blank?
        expect(el["style"]).not_to match(/color:|background[-\s]*:.*#|background[-\s]*:.*rgb/i),
          "Unexpected inline color style on #{el.name}.#{el['class']}: #{el['style']}"
      end
    end
  end

  # ── Sections and items ─────────────────────────────────────────────────────

  describe "with a single section" do
    subject(:node) { render_inline(described_class.new(sections: [ youtube_section ])) }

    it "renders the section title from i18n" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.sections.youtube"))
    end

    it "renders item labels" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.connect"))
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.disconnect"))
    end

    it "embeds data-insert on each item" do
      inserts = node.css("[data-pito--command-palette-target='item']").map { |el| el["data-insert"] }
      expect(inserts).to include("/connect", "/disconnect <@handle>")
    end

    it "embeds data-label on each item (present and lowercased)" do
      labels = node.css("[data-pito--command-palette-target='item']").map { |el| el["data-label"] }
      expect(labels).to all(be_a(String))
      labels.each { |l| expect(l).to eq(l.downcase) }
    end

    it "renders items with Stimulus item target" do
      items = node.css("[data-pito--command-palette-target='item']")
      expect(items.length).to eq(youtube_section[:items].length)
    end
  end

  describe "with multiple sections" do
    subject(:node) { render_inline(described_class.new(sections: [ youtube_section, general_section ])) }

    it "renders all section titles" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.sections.youtube"))
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.sections.general"))
    end

    it "renders items from all sections" do
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.login"))
      expect(node.text).to include(I18n.t("pito.palette.ctrl_k.commands.help"))
    end

    it "renders section-gap divs between sections (not after the last)" do
      gaps = node.css("[data-pito--command-palette-target='sectionGap']")
      expect(gaps.length).to eq(1)
    end
  end

  describe "with no sections" do
    it "renders without crashing" do
      node = render_inline(described_class.new(sections: []))
      expect(node.to_html).not_to be_empty
    end
  end

  # ── Scrollable list container ───────────────────────────────────────────────

  describe "scrollable container" do
    subject(:node) { render_inline(described_class.new(sections: [ youtube_section ])) }

    it "has the pito-hide-scrollbar class" do
      expect(node.css(".pito-hide-scrollbar")).not_to be_empty
    end

    it "has the list Stimulus target" do
      expect(node.css("[data-pito--command-palette-target='list']")).not_to be_empty
    end
  end
end
