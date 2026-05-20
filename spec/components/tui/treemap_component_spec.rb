require "rails_helper"

# Beta 4 Phase F2 — Tui::TreemapComponent.
#
# Share-of-total proportional tile layout via CSS flex. Tile width
# is `flex-grow: <raw value>`; tile opacity / saturation scales with
# `percent = value / total * 100`. The component does NOT sort
# internally — caller passes rows in the desired order.
RSpec.describe Tui::TreemapComponent, type: :component do
  let(:rows) do
    [
      { code: "US", value: 500 },
      { code: "UK", value: 300 },
      { code: "DE", value: 200 }
    ]
  end

  describe "wrapper" do
    it "renders a single `<div class=\"tui-treemap\">` root" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css("div.tui-treemap", count: 1)
    end

    it "renders one `.tui-treemap__tile` per row" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-treemap__tile", count: 3)
    end

    it "renders an empty `<div class=\"tui-treemap\">` when rows is empty" do
      render_inline(described_class.new(rows: []))

      expect(page).to have_css("div.tui-treemap")
      expect(page).to have_no_css(".tui-treemap__tile")
    end
  end

  describe "tile content" do
    it "renders the code in a `.tui-treemap__code` span" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-treemap__code", text: "US")
      expect(page).to have_css(".tui-treemap__code", text: "UK")
      expect(page).to have_css(".tui-treemap__code", text: "DE")
    end

    it "renders the percent in a `.tui-treemap__pct` span (suffixed with `%`)" do
      render_inline(described_class.new(rows: rows))

      # Total = 1000. US = 500 / 1000 = 50%.
      expect(page).to have_css(".tui-treemap__pct", text: "50.0%")
      expect(page).to have_css(".tui-treemap__pct", text: "30.0%")
      expect(page).to have_css(".tui-treemap__pct", text: "20.0%")
    end
  end

  describe "#total" do
    it "sums all `:value` entries" do
      component = described_class.new(rows: rows)

      expect(component.total).to eq(1000.0)
    end

    it "is 0.0 when rows is empty" do
      component = described_class.new(rows: [])

      expect(component.total).to eq(0.0)
    end
  end

  describe "#percent" do
    it "computes share-of-total percent rounded to 1 decimal" do
      component = described_class.new(rows: rows)

      expect(component.percent(500)).to eq(50.0)
      expect(component.percent(300)).to eq(30.0)
    end

    it "is 0 for a zero-total series (no division-by-zero)" do
      component = described_class.new(rows: [ { code: "X", value: 0 } ])

      expect(component.percent(0)).to eq(0)
    end
  end

  describe "tile inline style" do
    it "sets `flex-grow: <raw value>` on each tile" do
      render_inline(described_class.new(rows: rows))

      tiles = page.find_all(".tui-treemap__tile")
      expect(tiles[0][:style]).to include("flex-grow: 500")
      expect(tiles[1][:style]).to include("flex-grow: 300")
      expect(tiles[2][:style]).to include("flex-grow: 200")
    end

    it "sets `--pct: <percent>` on each tile" do
      render_inline(described_class.new(rows: rows))

      tiles = page.find_all(".tui-treemap__tile")
      expect(tiles[0][:style]).to include("--pct: 50.0")
      expect(tiles[1][:style]).to include("--pct: 30.0")
    end
  end

  describe "ordering" do
    it "preserves caller-provided order (no internal sort)" do
      reverse = rows.reverse # DE, UK, US
      render_inline(described_class.new(rows: reverse))

      codes = page.find_all(".tui-treemap__code").map(&:text)
      expect(codes).to eq(%w[DE UK US])
    end

    it "preserves an alphabetical caller ordering" do
      alpha = [
        { code: "DE", value: 200 },
        { code: "UK", value: 300 },
        { code: "US", value: 500 }
      ]
      render_inline(described_class.new(rows: alpha))

      codes = page.find_all(".tui-treemap__code").map(&:text)
      expect(codes).to eq(%w[DE UK US])
    end
  end

  describe "row coercion" do
    it "coerces rows via `.to_a`" do
      component = described_class.new(rows: rows.each)

      expect(component.rows.length).to eq(3)
    end
  end
end
