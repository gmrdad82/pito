require "rails_helper"

RSpec.describe Tui::ReindexProgressComponent, type: :component do
  describe "#initial_frame" do
    it "renders 9 characters including brackets (matches [reindex] width)" do
      expect(described_class.new(brand: "meilisearch").initial_frame.length).to eq(9)
    end

    it "starts with `=` at the leftmost position" do
      expect(described_class.new(brand: "voyage").initial_frame).to eq("[=------]")
    end
  end

  describe "rendering" do
    it "wraps in .tui-reindex-progress span with brand value" do
      render_inline(described_class.new(brand: "meilisearch"))
      expect(page).to have_css("span.tui-reindex-progress[data-tui-reindex-progress-brand-value='meilisearch']")
    end

    it "exposes aria-label with the brand" do
      render_inline(described_class.new(brand: "voyage"))
      expect(page).to have_css("span[aria-label='voyage reindex in progress']")
    end

    it "wires the Stimulus controller" do
      render_inline(described_class.new(brand: "meilisearch"))
      expect(page).to have_css("[data-controller='tui-reindex-progress']")
    end

    it "renders the initial frame text" do
      render_inline(described_class.new(brand: "voyage"))
      expect(page).to have_text("[=------]")
    end
  end

  describe "label width constant" do
    it "is 7 (matches reindex string length)" do
      expect(described_class::LABEL_WIDTH).to eq(7)
    end
  end
end
