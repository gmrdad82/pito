require "rails_helper"

# Beta 4 Phase F2 — Tui::PyramidComponent.
#
# Paired-bar comparison chart. Each row has `:left`, `:label`,
# `:right` values; bar widths are `(value / shared_max) * 100%`
# against the SHARED maximum across both sides so the two halves
# are directly comparable.
RSpec.describe Tui::PyramidComponent, type: :component do
  let(:rows) do
    [
      { left: 30, label: "18-24", right: 20 },
      { left: 50, label: "25-34", right: 40 },
      { left: 20, label: "35-44", right: 10 }
    ]
  end

  describe "wrapper" do
    it "renders a single `<div class=\"tui-pyramid\">` root" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css("div.tui-pyramid", count: 1)
    end

    it "renders one `.tui-pyramid__row` per input row" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-pyramid__row", count: 3)
    end

    it "renders an empty `<div class=\"tui-pyramid\">` when rows is empty" do
      render_inline(described_class.new(rows: []))

      expect(page).to have_css("div.tui-pyramid")
      expect(page).to have_no_css(".tui-pyramid__row")
    end
  end

  describe "row content (5-column grid)" do
    it "renders 5 spans per row (left-value | left-bar | label | right-bar | right-value)" do
      render_inline(described_class.new(rows: rows))

      first_row = page.find_all(".tui-pyramid__row").first
      expect(first_row).to have_css(".tui-pyramid__left-value")
      expect(first_row).to have_css(".tui-pyramid__left-bar")
      expect(first_row).to have_css(".tui-pyramid__label")
      expect(first_row).to have_css(".tui-pyramid__right-bar")
      expect(first_row).to have_css(".tui-pyramid__right-value")
    end

    it "renders the label text" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-pyramid__label", text: "18-24")
      expect(page).to have_css(".tui-pyramid__label", text: "25-34")
    end

    it "suffixes left + right values with literal `%`" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-pyramid__left-value", text: "30%")
      expect(page).to have_css(".tui-pyramid__right-value", text: "20%")
    end
  end

  describe "#max_value (shared across both sides)" do
    it "is the highest value across `:left` and `:right`" do
      component = described_class.new(rows: rows)

      # left max = 50, right max = 40 → shared max = 50
      expect(component.max_value).to eq(50.0)
    end

    it "picks from the right side when right exceeds left" do
      component = described_class.new(rows: [ { left: 10, label: "x", right: 100 } ])

      expect(component.max_value).to eq(100.0)
    end

    it "returns 1.0 when rows is empty" do
      component = described_class.new(rows: [])

      expect(component.max_value).to eq(1.0)
    end
  end

  describe "#percent (cross-side comparable)" do
    it "computes percent against the shared max" do
      component = described_class.new(rows: rows)

      # shared max = 50
      expect(component.percent(50)).to eq(100.0)
      expect(component.percent(25)).to eq(50.0)
      expect(component.percent(10)).to eq(20.0)
    end

    it "returns 0 when shared max is zero (no division-by-zero)" do
      component = described_class.new(rows: [ { left: 0, label: "x", right: 0 } ])

      expect(component.percent(0)).to eq(0)
    end

    it "rounds to 1 decimal" do
      component = described_class.new(rows: [ { left: 100, label: "x", right: 0 } ])

      expect(component.percent(33)).to eq(33.0)
    end
  end

  describe "bar inline style (--pct)" do
    it "sets `--pct: <value>%` on left bar" do
      render_inline(described_class.new(rows: rows))

      bar = page.find_all(".tui-pyramid__left-bar").first
      expect(bar[:style]).to include("--pct:")
      expect(bar[:style]).to include("%")
    end

    it "sets `--pct: <value>%` on right bar" do
      render_inline(described_class.new(rows: rows))

      bar = page.find_all(".tui-pyramid__right-bar").first
      expect(bar[:style]).to include("--pct:")
      expect(bar[:style]).to include("%")
    end

    it "left bar of the largest left value is at --pct: 100%" do
      render_inline(described_class.new(rows: rows))

      # rows[1] has left: 50 which is the shared max.
      bars = page.find_all(".tui-pyramid__left-bar")
      expect(bars[1][:style]).to include("--pct: 100")
    end
  end

  describe "row coercion" do
    it "coerces rows via `.to_a`" do
      component = described_class.new(rows: rows.each)

      expect(component.rows.length).to eq(3)
    end
  end
end
