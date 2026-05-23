require "rails_helper"

# SortableHeaderComponent spec — V4 contract (locked 2026-05-23, FB-189).
#
# Under V4 the active sort indicator is a `border-bottom` style on the
# `<th>` (solid = ascending, dashed = descending, color = section
# accent). The component itself emits a neutral `<th class="sortable">
# <span class="sortable-label">label</span></th>` — direction-encoding
# classes (`sort-asc` / `sort-desc`) are applied at runtime by
# `sortable_table_controller.js` (JS-driven) or by
# `ApplicationHelper#sort_link_to` (URL-driven server render).
#
# This spec covers the component's static emission contract only; the
# V4 underline style itself lives in CSS (`app/assets/tailwind/
# application.css`) and is purely visual.
RSpec.describe SortableHeaderComponent, type: :component do
  describe "rendered DOM" do
    subject(:rendered) do
      render_inline(described_class.new(label: "rows", sort_type: "number", numeric: true))
    end

    it "renders a <th> carrying the .sortable class for V4 underline targeting" do
      th = rendered.css("th").first
      expect(th).to be_present
      expect(th["class"]).to include("sortable")
    end

    it "applies the .num class when numeric: true is passed" do
      th = rendered.css("th").first
      expect(th["class"]).to include("num")
    end

    it "wires the click->sortable-table#sort Stimulus action" do
      th = rendered.css("th").first
      expect(th["data-action"]).to eq("click->sortable-table#sort")
    end

    it "emits the sort-type attribute so the JS controller can pick the comparator" do
      th = rendered.css("th").first
      expect(th["data-sort-type"]).to eq("number")
    end

    it "wraps the label in a .sortable-label span (V4 inner shape)" do
      span = rendered.css("th > span.sortable-label").first
      expect(span).to be_present
      expect(span.text.strip).to eq("rows")
    end

    it "does NOT emit the legacy ::after arrow class or glyph in static HTML" do
      # V4 has no glyph; the underline is pure CSS on the active state.
      th = rendered.css("th").first
      expect(th.text).not_to include("▲")
      expect(th.text).not_to include("▼")
    end
  end

  describe "optional kwargs" do
    it "omits .num when numeric defaults to false" do
      rendered = render_inline(described_class.new(label: "name", sort_type: "string"))
      th = rendered.css("th").first
      expect(th["class"]).not_to include("num")
    end

    it "appends extra_class when provided" do
      rendered = render_inline(
        described_class.new(label: "name", sort_type: "string", extra_class: "col-wide")
      )
      th = rendered.css("th").first
      expect(th["class"]).to include("col-wide")
      expect(th["class"]).to include("sortable")
    end
  end
end
