require "rails_helper"

# Beta 4 Phase F2 — Tui::HeatmapComponent.
#
# 7-row (Mon..Sun) × N-col (default 24-hour) heatmap. Each cell's
# `--intensity` CSS variable is `value / series_max` clamped to
# [0, 1]; missing day keys or short arrays render at intensity 0.
# Coverage targets the DAYS constant + the intensity math + the
# safe-defaults branches (missing data, all-zero, custom hours).
RSpec.describe Tui::HeatmapComponent, type: :component do
  describe "DAYS constant" do
    it "lists Mon..Sun in order" do
      expect(described_class::DAYS).to eq(%w[Mon Tue Wed Thu Fri Sat Sun])
    end

    it "is frozen" do
      expect(described_class::DAYS).to be_frozen
    end
  end

  describe "structure" do
    it "renders 7 day rows regardless of `data:` key coverage" do
      render_inline(described_class.new(data: { "Mon" => [ 1 ] * 24 }))

      expect(page).to have_css("tbody tr", count: 7)
    end

    it "renders all 7 day labels" do
      render_inline(described_class.new(data: {}))

      %w[Mon Tue Wed Thu Fri Sat Sun].each do |label|
        expect(page).to have_css(".tui-heatmap__day", text: label)
      end
    end

    it "renders 24 hour columns by default" do
      render_inline(described_class.new(data: { "Mon" => [ 1 ] * 24 }))

      # 7 day labels + (7 * 24) hour cells; check hour cells:
      expect(page).to have_css(".tui-heatmap__cell", count: 7 * 24)
    end

    it "renders 24 hour-label headers (zero-padded)" do
      render_inline(described_class.new(data: {}))

      expect(page).to have_css(".tui-heatmap__hour-label", count: 24)
      expect(page).to have_css(".tui-heatmap__hour-label", text: "00")
      expect(page).to have_css(".tui-heatmap__hour-label", text: "09")
      expect(page).to have_css(".tui-heatmap__hour-label", text: "23")
    end
  end

  describe "custom hours" do
    it "respects a custom `hours:` array that shrinks the column count" do
      render_inline(described_class.new(data: {}, hours: (8..20).to_a))

      expect(page).to have_css(".tui-heatmap__hour-label", count: 13)
      expect(page).to have_css(".tui-heatmap__cell", count: 7 * 13)
    end

    it "zero-pads single-digit hour labels" do
      render_inline(described_class.new(data: {}, hours: [ 0, 5, 23 ]))

      expect(page).to have_css(".tui-heatmap__hour-label", text: "00")
      expect(page).to have_css(".tui-heatmap__hour-label", text: "05")
      expect(page).to have_css(".tui-heatmap__hour-label", text: "23")
    end
  end

  describe "#intensity" do
    let(:data) do
      {
        "Mon" => Array.new(24, 0).tap { |a| a[12] = 10 },
        "Tue" => Array.new(24, 0).tap { |a| a[12] = 5 }
      }
    end

    it "is 0 for a missing day key" do
      component = described_class.new(data: data)

      expect(component.intensity("Wed", 12)).to eq(0)
    end

    it "is 0 for a missing hour index" do
      component = described_class.new(data: { "Mon" => [ 1, 2, 3 ] })

      expect(component.intensity("Mon", 23)).to eq(0)
    end

    it "is `value / series_max` clamped to [0, 1]" do
      component = described_class.new(data: data)

      # max is 10 (Mon hour 12). Tue hour 12 is 5 → 0.5.
      expect(component.intensity("Mon", 12)).to eq(1.0)
      expect(component.intensity("Tue", 12)).to eq(0.5)
    end

    it "is 0 when the entire data is all-zero (no division-by-zero)" do
      component = described_class.new(data: { "Mon" => Array.new(24, 0) })

      expect(component.intensity("Mon", 0)).to eq(0)
    end

    it "is 0 when data is empty" do
      component = described_class.new(data: {})

      expect(component.intensity("Mon", 0)).to eq(0)
    end
  end

  describe "intensity inline style" do
    it "sets `--intensity: <value>` on each cell" do
      data = { "Mon" => Array.new(24, 0).tap { |a| a[5] = 10 } }
      render_inline(described_class.new(data: data))

      # Find one cell with the max intensity (Mon, hour 5).
      cell = page.find_all(".tui-heatmap__cell").detect do |c|
        c[:style]&.include?("--intensity: 1")
      end
      expect(cell).not_to be_nil
    end

    it "renders all cells with `--intensity: 0` when all data is zero" do
      data = { "Mon" => Array.new(24, 0) }
      render_inline(described_class.new(data: data))

      page.find_all(".tui-heatmap__cell").each do |cell|
        expect(cell[:style]).to include("--intensity: 0")
      end
    end

    it "does not raise when data is fully empty" do
      expect {
        render_inline(described_class.new(data: {}))
      }.not_to raise_error
    end
  end
end
