require "rails_helper"

# Beta 4 Phase F2 — Tui::BarChartComponent.
#
# Horizontal bar chart over a list of `{label:, value:}` rows. Bar
# width is `(value / series_max) * 100%` so all bars in the chart
# share the same denominator (the series max, not the total). The
# component takes an optional `value_format:` Proc to humanize the
# displayed number. Spec coverage targets the percent math, the
# div-by-zero guard, the formatter invocation, and the empty-rows
# branch.
RSpec.describe Tui::BarChartComponent, type: :component do
  let(:rows) do
    [
      { label: "alpha",   value: 100 },
      { label: "beta",    value: 50 },
      { label: "gamma",   value: 25 }
    ]
  end

  describe "wrapper" do
    it "renders a single `<div class=\"tui-bar-chart\">` root" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css("div.tui-bar-chart", count: 1)
    end

    it "renders one `.tui-bar-chart__row` per row" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-bar-chart__row", count: 3)
    end
  end

  describe "empty rows" do
    it "renders an empty `<div class=\"tui-bar-chart\">` when rows is empty" do
      render_inline(described_class.new(rows: []))

      expect(page).to have_css("div.tui-bar-chart")
      expect(page).to have_no_css(".tui-bar-chart__row")
    end
  end

  describe "row content" do
    it "renders the label in a `.tui-bar-chart__label` span" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-bar-chart__label", text: "alpha")
      expect(page).to have_css(".tui-bar-chart__label", text: "beta")
    end

    it "renders the bar inside a `.tui-bar-chart__bar-wrap` wrapper" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-bar-chart__bar-wrap", count: 3)
      expect(page).to have_css(".tui-bar-chart__bar-wrap .tui-bar-chart__bar", count: 3)
    end

    it "renders the value in a `.tui-bar-chart__value` span" do
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css(".tui-bar-chart__value", text: "100")
      expect(page).to have_css(".tui-bar-chart__value", text: "50")
    end
  end

  describe "#max_value" do
    it "returns the highest `:value` across rows" do
      component = described_class.new(rows: rows)

      expect(component.max_value).to eq(100.0)
    end

    it "returns 1.0 when rows is empty (no division-by-zero)" do
      component = described_class.new(rows: [])

      expect(component.max_value).to eq(1.0)
    end
  end

  describe "#percent" do
    it "computes bar percent against the SERIES MAX (not total)" do
      component = described_class.new(rows: rows)

      # max = 100. percent of 100 = 100; of 50 = 50; of 25 = 25.
      expect(component.percent(100)).to eq(100.0)
      expect(component.percent(50)).to eq(50.0)
      expect(component.percent(25)).to eq(25.0)
    end

    it "returns 0 for a zero-max series (no division-by-zero)" do
      component = described_class.new(rows: [ { label: "a", value: 0 }, { label: "b", value: 0 } ])

      # max is 0, all values produce 0 percent
      expect(component.percent(0)).to eq(0)
    end

    it "rounds to 1 decimal" do
      component = described_class.new(rows: rows)

      expect(component.percent(33)).to eq(33.0)
    end
  end

  describe "bar width inline style" do
    it "sets `width: <percent>%` on `.tui-bar-chart__bar`" do
      render_inline(described_class.new(rows: rows))

      bar = page.find_all(".tui-bar-chart__bar").first
      expect(bar[:style]).to include("width: 100")
    end

    it "renders 0% bar width when the series max is zero" do
      render_inline(described_class.new(rows: [ { label: "a", value: 0 } ]))

      bar = page.find(".tui-bar-chart__bar")
      expect(bar[:style]).to include("width: 0")
    end
  end

  describe "#format_value" do
    it "defaults to `.to_s` when no formatter is given" do
      component = described_class.new(rows: rows)

      expect(component.format_value(42)).to eq("42")
      expect(component.format_value(1234)).to eq("1234")
    end

    it "applies the `value_format:` Proc when given" do
      formatter = ->(n) { "#{n}k" }
      component = described_class.new(rows: rows, value_format: formatter)

      expect(component.format_value(42)).to eq("42k")
    end

    it "uses the formatter in render output" do
      formatter = ->(n) { "#{n} views" }
      render_inline(described_class.new(rows: [ { label: "alpha", value: 100 } ], value_format: formatter))

      expect(page).to have_css(".tui-bar-chart__value", text: "100 views")
    end
  end

  describe "row coercion" do
    it "coerces rows via `.to_a`" do
      component = described_class.new(rows: [ { label: "a", value: 1 } ].each)

      expect(component.rows.length).to eq(1)
    end
  end
end
