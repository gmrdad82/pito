require "rails_helper"

RSpec.describe Tui::SegmentedBarComponent, type: :component do
  describe "#cells" do
    context "with default 10 segments" do
      it "renders 10 filled at 100%" do
        expect(described_class.new(percent: 100).cells).to eq("▰" * 10)
      end

      it "renders 10 empty at 0%" do
        expect(described_class.new(percent: 0).cells).to eq("▱" * 10)
      end

      it "renders 8 filled + 2 empty at 80%" do
        expect(described_class.new(percent: 80).cells).to eq("▰▰▰▰▰▰▰▰▱▱")
      end

      it "renders 6 filled + 4 empty at 60%" do
        expect(described_class.new(percent: 60).cells).to eq("▰▰▰▰▰▰▱▱▱▱")
      end

      it "renders 4 filled + 6 empty at 40%" do
        expect(described_class.new(percent: 40).cells).to eq("▰▰▰▰▱▱▱▱▱▱")
      end

      it "renders 2 filled + 8 empty at 20%" do
        expect(described_class.new(percent: 20).cells).to eq("▰▰▱▱▱▱▱▱▱▱")
      end

      it "renders 1 filled + 9 empty at 10%" do
        expect(described_class.new(percent: 10).cells).to eq("▰▱▱▱▱▱▱▱▱▱")
      end
    end

    context "with custom segments" do
      it "honors segments: 5" do
        expect(described_class.new(percent: 60, segments: 5).cells).to eq("▰▰▰▱▱")
      end

      it "honors segments: 20" do
        expect(described_class.new(percent: 50, segments: 20).cells.length).to eq(20)
        expect(described_class.new(percent: 50, segments: 20).cells).to eq(("▰" * 10) + ("▱" * 10))
      end
    end

    context "edge cases" do
      it "clamps negative percent to 0" do
        expect(described_class.new(percent: -10).cells).to eq("▱" * 10)
      end

      it "clamps >100 percent to 100" do
        expect(described_class.new(percent: 150).cells).to eq("▰" * 10)
      end

      it "rounds fractional fills (51% rounds to 5/10)" do
        expect(described_class.new(percent: 51).cells).to eq("▰▰▰▰▰▱▱▱▱▱")
      end

      it "rounds fractional fills (55% rounds to 6/10)" do
        expect(described_class.new(percent: 55).cells).to eq("▰▰▰▰▰▰▱▱▱▱")
      end
    end
  end

  describe "rendering" do
    it "wraps cells in tui-segmented-bar span" do
      render_inline(described_class.new(percent: 50))
      expect(page).to have_css("span.tui-segmented-bar")
    end

    it "sets aria-label to rounded percent" do
      render_inline(described_class.new(percent: 73.8))
      expect(page).to have_css("span[aria-label='74%']")
    end
  end
end
