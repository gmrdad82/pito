require "rails_helper"

RSpec.describe Tui::ReindexProgressComponent, type: :component do
  describe "#initial_frame" do
    it "renders 9 characters total (matches `[reindex]` width)" do
      expect(described_class.new(brand: "meilisearch").initial_frame.length).to eq(9)
    end

    it "renders `[=------]` (bracket + `=` + 6 dashes + bracket)" do
      expect(described_class.new(brand: "voyage").initial_frame).to eq("[=------]")
    end

    it "starts and ends with literal brackets" do
      frame = described_class.new(brand: "meilisearch").initial_frame
      expect(frame[0]).to eq("[")
      expect(frame[-1]).to eq("]")
    end

    it "uses only `[`, `]`, `=`, `-` characters" do
      frame = described_class.new(brand: "meilisearch").initial_frame
      expect(frame).to match(/\A\[[=\-]+\]\z/)
    end

    it "contains exactly one `=` and `INNER_WIDTH - 1` dashes inside the brackets" do
      frame = described_class.new(brand: "meilisearch").initial_frame
      inner = frame[1..-2]
      expect(inner.length).to eq(described_class::INNER_WIDTH)
      expect(inner.count("=")).to eq(1)
      expect(inner.count("-")).to eq(described_class::INNER_WIDTH - 1)
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

    it "exposes the inner width (7) as the Stimulus width data-value" do
      render_inline(described_class.new(brand: "voyage"))
      expect(page).to have_css("[data-tui-reindex-progress-width-value='7']")
    end
  end

  describe "width constants" do
    it "INNER_WIDTH is 7 (matches `reindex` letter count)" do
      expect(described_class::INNER_WIDTH).to eq(7)
    end

    it "TOTAL_WIDTH is 9 (matches `[reindex]` total width)" do
      expect(described_class::TOTAL_WIDTH).to eq(9)
    end
  end
end
