require "rails_helper"

# Beta 4 Phase F2 — Tui::TableComponent.
#
# Minimal `<table>` primitive with hairline row separators and
# per-column alignment driven by an `align:` array. Headers + cells
# render as-is (caller decides case + HTML safety). Coverage targets
# the alignment math, empty-rows branch, and the `.tui-table__row`
# class hook that the CSS uses to strip the last row's border via
# `:last-child`.
RSpec.describe Tui::TableComponent, type: :component do
  let(:headers) { %w[user pinged status] }
  let(:rows) do
    [
      [ "alice", "now", "active" ],
      [ "bob",   "1m ago", "idle" ]
    ]
  end

  describe "wrapper" do
    it "renders a single `<table class=\"tui-table\">` root" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css("table.tui-table", count: 1)
    end

    it "renders a `<thead>` and a `<tbody>`" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css("table.tui-table > thead")
      expect(page).to have_css("table.tui-table > tbody")
    end
  end

  describe "headers" do
    it "renders one `<th>` per header" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css(".tui-table__th", count: 3)
    end

    it "renders header text as-is (caller decides case)" do
      render_inline(described_class.new(headers: %w[USER pinged], rows: []))

      expect(page).to have_css(".tui-table__th", text: "USER")
      expect(page).to have_css(".tui-table__th", text: "pinged")
    end

    it "renders thead even with an empty rows array" do
      render_inline(described_class.new(headers: headers, rows: []))

      expect(page).to have_css("thead .tui-table__th", count: 3)
    end

    it "applies the default `:left` alignment when no `align:` is given" do
      render_inline(described_class.new(headers: headers, rows: rows))

      headers.each_index do |i|
        expect(page).to have_css(".tui-table__th--left", count: headers.length)
      end
    end
  end

  describe "rows + tbody" do
    it "renders one `<tr class=\"tui-table__row\">` per row" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css("tbody tr.tui-table__row", count: 2)
    end

    it "renders one `<td class=\"tui-table__td\">` per cell" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css(".tui-table__td", count: 6)
    end

    it "renders cell content as-is" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css(".tui-table__td", text: "alice")
      expect(page).to have_css(".tui-table__td", text: "bob")
    end

    it "renders no `<tr>` in tbody when rows is empty" do
      render_inline(described_class.new(headers: headers, rows: []))

      expect(page).to have_no_css("tbody tr")
    end
  end

  describe "per-column alignment" do
    it "applies the `:right` modifier class for right-aligned columns" do
      render_inline(described_class.new(
        headers: %w[name count],
        rows:    [ [ "alice", 42 ] ],
        align:   [ :left, :right ]
      ))

      expect(page).to have_css(".tui-table__th--right", text: "count")
      expect(page).to have_css(".tui-table__td--right", text: "42")
    end

    it "applies the `:center` modifier class for centered columns" do
      render_inline(described_class.new(
        headers: %w[flag value],
        rows:    [ [ "x", "y" ] ],
        align:   [ :center, :left ]
      ))

      expect(page).to have_css(".tui-table__th--center", text: "flag")
      expect(page).to have_css(".tui-table__td--center", text: "x")
    end

    it "applies the matching td alignment to each cell column" do
      render_inline(described_class.new(
        headers: %w[name pinged],
        rows:    [ [ "alice", "now" ] ],
        align:   [ :left, :right ]
      ))

      expect(page).to have_css(".tui-table__td--left", text: "alice")
      expect(page).to have_css(".tui-table__td--right", text: "now")
    end

    it "defaults missing align entries to `:left`" do
      render_inline(described_class.new(
        headers: %w[a b c],
        rows:    [ [ "1", "2", "3" ] ],
        align:   [ :right ] # only first explicit
      ))

      expect(page).to have_css(".tui-table__th--right", text: "a")
      expect(page).to have_css(".tui-table__th--left", text: "b")
      expect(page).to have_css(".tui-table__th--left", text: "c")
    end
  end

  describe "#col_align helper" do
    it "returns the requested align value when set" do
      component = described_class.new(headers: %w[a b], rows: [], align: [ :left, :right ])

      expect(component.col_align(0)).to eq(:left)
      expect(component.col_align(1)).to eq(:right)
    end

    it "returns `:left` when align entry is missing" do
      component = described_class.new(headers: %w[a b], rows: [], align: [ :right ])

      expect(component.col_align(1)).to eq(:left)
    end

    it "returns `:left` when align is not given at all" do
      component = described_class.new(headers: %w[a], rows: [])

      expect(component.col_align(0)).to eq(:left)
    end
  end

  describe ".tui-table__row class hook (last-row border strip via :last-child)" do
    it "all body rows carry the `.tui-table__row` class — CSS strips the last via `:last-child`" do
      render_inline(described_class.new(headers: headers, rows: rows))

      expect(page).to have_css("tbody tr.tui-table__row", count: rows.length)
    end
  end
end
