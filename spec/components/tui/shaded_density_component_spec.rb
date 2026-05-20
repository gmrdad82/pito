require "rails_helper"

RSpec.describe Tui::ShadedDensityComponent, type: :component do
  describe "#cells" do
    context "with width: 8 (default)" do
      it "renders all full at 100%" do
        expect(described_class.new(percent: 100).cells.join).to eq("████████")
      end

      it "renders all empty at 0%" do
        expect(described_class.new(percent: 0).cells.join).to eq("░░░░░░░░")
      end

      it "renders 4 full + 4 empty at 50%" do
        expect(described_class.new(percent: 50).cells.join).to eq("████░░░░")
      end

      it "renders 2 full + 6 empty at 25%" do
        expect(described_class.new(percent: 25).cells.join).to eq("██░░░░░░")
      end

      it "renders 1 full + 7 empty at 12.5%" do
        expect(described_class.new(percent: 12.5).cells.join).to eq("█░░░░░░░")
      end

      it "renders 7 full + empty boundary at 87.5%" do
        expect(described_class.new(percent: 87.5).cells.join).to eq("███████░")
      end

      it "shows ▒ boundary at 92%" do
        expect(described_class.new(percent: 92).cells.join).to eq("███████▒")
      end

      it "shows ▓ boundary at 96%" do
        expect(described_class.new(percent: 96).cells.join).to eq("███████▓")
      end
    end

    context "with custom width" do
      it "honors width: 4" do
        expect(described_class.new(percent: 50, width: 4).cells.join).to eq("██░░")
      end

      it "honors width: 16" do
        expect(described_class.new(percent: 100, width: 16).cells.length).to eq(16)
        expect(described_class.new(percent: 100, width: 16).cells.join).to eq("█" * 16)
      end

      it "honors width: 1" do
        expect(described_class.new(percent: 100, width: 1).cells.join).to eq("█")
        expect(described_class.new(percent: 0, width: 1).cells.join).to eq("░")
        expect(described_class.new(percent: 50, width: 1).cells.length).to eq(1)
      end
    end

    context "edge cases — percent clamping" do
      it "clamps negative percent to 0" do
        expect(described_class.new(percent: -10).cells.join).to eq("░░░░░░░░")
      end

      it "clamps >100 percent to 100" do
        expect(described_class.new(percent: 150).cells.join).to eq("████████")
      end

      it "handles fractional percent (e.g. 33.33%)" do
        result = described_class.new(percent: 33.33).cells.join
        # 33.33% of 24 = 7.999 → rounds to 8 sub-units = 2 full + 2 empty (8/12 cell)
        # Actually: filled_units = (33.33/100 * 24).round = 8. Cell 3: cell_start=6, cell_end=9, filled=8 → BLOCKS[2]=▓
        expect(result).to eq("██▓░░░░░")
      end
    end

    context "type coercion" do
      it "accepts string percent" do
        expect(described_class.new(percent: "50").cells.join).to eq("████░░░░")
      end

      it "accepts integer percent" do
        expect(described_class.new(percent: 50).cells.join).to eq("████░░░░")
      end
    end

    context "uniform-fill semantics — covered cells are always solid █" do
      # The whole point of (B) uniform fill vs (A) gradient ramp:
      # covered cells render as █ not as ░▒▓ ramp.
      it "covered cells render as full block at 75%" do
        cells = described_class.new(percent: 75).cells
        # 75% of 24 = 18. Cell 6: cell_end=18, filled≥18 → █. Cells 1-6 = █.
        expect(cells[0..5]).to all(eq("█"))
      end

      it "no gradient ramp visible inside the covered portion" do
        cells = described_class.new(percent: 100, width: 12).cells
        expect(cells.uniq).to eq([ "█" ])
      end
    end
  end

  describe "rendering" do
    it "wraps cells in a span with tui-shaded-density class" do
      render_inline(described_class.new(percent: 50))
      expect(page).to have_css("span.tui-shaded-density")
    end

    it "renders the cells joined as text" do
      render_inline(described_class.new(percent: 100, width: 4))
      expect(page).to have_text("████")
    end

    it "sets aria-label to rounded percent" do
      render_inline(described_class.new(percent: 87.6))
      expect(page).to have_css("span[aria-label='88%']")
    end
  end
end
