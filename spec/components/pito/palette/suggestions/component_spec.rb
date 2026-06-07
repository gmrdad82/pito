# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::Suggestions::Component, type: :component do
  let(:items) do
    [
      { label: "/config", description: "Configure settings", masked: false },
      { label: "/help",   description: "Show help",          masked: false },
      { label: "/secret", description: "Hidden command",     masked: true  }
    ]
  end

  describe "row rendering" do
    subject(:node) { render_inline(described_class.new(mode: :slash, items: items)) }

    it "renders one .pito-suggestions-row per item" do
      expect(node.css(".pito-suggestions-row").length).to eq(3)
    end

    it "shows each item's label" do
      labels = node.css(".pito-suggestions-row").map(&:text)
      expect(labels.any? { |t| t.include?("/config") }).to be true
      expect(labels.any? { |t| t.include?("/help") }).to be true
    end

    it "shows each item's description" do
      full_text = node.text
      expect(full_text).to include("Configure settings")
      expect(full_text).to include("Show help")
    end

    it "attaches data-index to each row" do
      rows = node.css(".pito-suggestions-row")
      expect(rows[0]["data-index"]).to eq("0")
      expect(rows[1]["data-index"]).to eq("1")
      expect(rows[2]["data-index"]).to eq("2")
    end
  end

  describe "selected_index" do
    it "marks the correct row with is-selected" do
      node = render_inline(described_class.new(mode: :slash, items: items, selected_index: 1))
      rows = node.css(".pito-suggestions-row")
      expect(rows[0]["class"]).not_to include("is-selected")
      expect(rows[1]["class"]).to include("is-selected")
      expect(rows[2]["class"]).not_to include("is-selected")
    end

    it "defaults to selecting the first row" do
      node = render_inline(described_class.new(mode: :slash, items: items))
      rows = node.css(".pito-suggestions-row")
      expect(rows[0]["class"]).to include("is-selected")
      expect(rows[1]["class"]).not_to include("is-selected")
    end
  end

  describe "mode: :slash" do
    subject(:node) { render_inline(described_class.new(mode: :slash, items: items)) }

    it "renders the bar with data-accent=purple" do
      bar = node.css(".pito-segment__bar").first
      expect(bar["data-accent"]).to eq("purple")
    end

    it "renders the cursor echo char /" do
      expect(node.css(".pito-cursor").first.text).to eq("/")
    end
  end

  describe "mode: :hashtag" do
    subject(:node) { render_inline(described_class.new(mode: :hashtag, items: items)) }

    it "renders the bar with data-accent=cyan" do
      bar = node.css(".pito-segment__bar").first
      expect(bar["data-accent"]).to eq("cyan")
    end

    it "renders the cursor echo char #" do
      expect(node.css(".pito-cursor").first.text).to eq("#")
    end
  end

  describe "masked items" do
    subject(:node) { render_inline(described_class.new(mode: :slash, items: items)) }

    it "renders a masked affordance for masked: true items" do
      masked_row = node.css(".pito-suggestions-row")[2]
      expect(masked_row.css(".text-fg-faded").first).to be_present
      expect(masked_row.css(".text-fg-faded").first.text).to include("hidden")
    end

    it "does not render the masked affordance for masked: false items" do
      unmasked_row = node.css(".pito-suggestions-row")[0]
      expect(unmasked_row.css(".text-fg-faded").first).to be_nil
    end
  end

  describe "empty items" do
    subject(:node) { render_inline(described_class.new(mode: :slash, items: [])) }

    it "renders no rows" do
      expect(node.css(".pito-suggestions-row").length).to eq(0)
    end

    it "does not crash and renders the palette shell" do
      expect(node.css(".pito-suggestions-palette").first).to be_present
    end
  end

  describe "typed text" do
    it "shows the typed string on the echo line" do
      node = render_inline(described_class.new(mode: :slash, items: [], typed: "hel"))
      expect(node.text).to include("hel")
    end
  end

  describe "stable hook classes and attributes" do
    subject(:node) { render_inline(described_class.new(mode: :slash, items: items)) }

    it "gives the root element the pito-suggestions-palette class" do
      expect(node.css(".pito-suggestions-palette").first).to be_present
    end
  end
end
