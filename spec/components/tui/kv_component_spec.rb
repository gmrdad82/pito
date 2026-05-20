require "rails_helper"

# Beta 4 Phase F3-DEEP-C — Tui::KvComponent.
#
# Definition-list (dl/dt/dd) companion to `.tui-table`. Accepts
# rows as `[label, value]` pairs OR `{label:, value:}` hashes;
# coverage targets the normalization logic + the dl/dt/dd shape +
# coercion of non-string values via `.to_s`.
RSpec.describe Tui::KvComponent, type: :component do
  describe "wrapper" do
    it "renders a single `<dl class=\"tui-kv\">` root" do
      render_inline(described_class.new(rows: [ [ "name", "alice" ] ]))

      expect(page).to have_css("dl.tui-kv", count: 1)
    end

    it "renders one `<dt>` + `<dd>` pair per row" do
      render_inline(described_class.new(rows: [ [ "a", "1" ], [ "b", "2" ], [ "c", "3" ] ]))

      expect(page).to have_css("dl.tui-kv > dt", count: 3)
      expect(page).to have_css("dl.tui-kv > dd", count: 3)
    end

    it "renders an empty `<dl>` when rows is empty (no children, no error)" do
      render_inline(described_class.new(rows: []))

      expect(page).to have_css("dl.tui-kv")
      expect(page).to have_no_css("dl.tui-kv > dt")
      expect(page).to have_no_css("dl.tui-kv > dd")
    end
  end

  describe "array-of-arrays input" do
    it "uses index 0 as the label and index 1 as the value" do
      render_inline(described_class.new(rows: [ [ "name", "alice" ], [ "role", "admin" ] ]))

      expect(page).to have_css("dt", text: "name")
      expect(page).to have_css("dd", text: "alice")
      expect(page).to have_css("dt", text: "role")
      expect(page).to have_css("dd", text: "admin")
    end
  end

  describe "hash input" do
    it "reads `:label` and `:value` from each hash" do
      rows = [
        { label: "name", value: "alice" },
        { label: "role", value: "admin" }
      ]
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css("dt", text: "name")
      expect(page).to have_css("dd", text: "alice")
      expect(page).to have_css("dt", text: "role")
      expect(page).to have_css("dd", text: "admin")
    end
  end

  describe "mixed input (arrays AND hashes)" do
    it "normalizes both shapes in the same call" do
      rows = [
        [ "name", "alice" ],
        { label: "role", value: "admin" }
      ]
      render_inline(described_class.new(rows: rows))

      expect(page).to have_css("dt", text: "name")
      expect(page).to have_css("dd", text: "alice")
      expect(page).to have_css("dt", text: "role")
      expect(page).to have_css("dd", text: "admin")
    end
  end

  describe "#normalized_rows" do
    it "returns array of `[String, String]` tuples from arrays" do
      component = described_class.new(rows: [ [ "a", "1" ], [ "b", "2" ] ])

      expect(component.normalized_rows).to eq([ [ "a", "1" ], [ "b", "2" ] ])
    end

    it "returns array of `[String, String]` tuples from hashes" do
      component = described_class.new(rows: [ { label: "a", value: "1" }, { label: "b", value: "2" } ])

      expect(component.normalized_rows).to eq([ [ "a", "1" ], [ "b", "2" ] ])
    end

    it "coerces Integer values via `.to_s`" do
      component = described_class.new(rows: [ [ "count", 42 ] ])

      expect(component.normalized_rows).to eq([ [ "count", "42" ] ])
    end

    it "coerces Date values via `.to_s`" do
      date = Date.new(2026, 5, 20)
      component = described_class.new(rows: [ [ "released", date ] ])

      expect(component.normalized_rows).to eq([ [ "released", date.to_s ] ])
    end

    it "coerces nil to empty string" do
      component = described_class.new(rows: [ [ "field", nil ] ])

      expect(component.normalized_rows).to eq([ [ "field", "" ] ])
    end

    it "coerces non-string labels via `.to_s`" do
      component = described_class.new(rows: [ [ :name, "alice" ] ])

      expect(component.normalized_rows).to eq([ [ "name", "alice" ] ])
    end

    it "coerces symbol values via `.to_s` (hash input)" do
      component = described_class.new(rows: [ { label: "status", value: :active } ])

      expect(component.normalized_rows).to eq([ [ "status", "active" ] ])
    end
  end

  describe "non-string value rendering" do
    it "renders Integer values as their `.to_s` form" do
      render_inline(described_class.new(rows: [ [ "count", 42 ] ]))

      expect(page).to have_css("dd", text: "42")
    end

    it "renders nil values as empty `<dd>`" do
      render_inline(described_class.new(rows: [ [ "field", nil ] ]))

      expect(page).to have_css("dd", text: "")
    end
  end

  describe "row coercion" do
    it "coerces rows via `.to_a`" do
      component = described_class.new(rows: [ [ "a", "1" ] ].each)

      expect(component.rows.length).to eq(1)
    end
  end

  describe ".tui-kv class hook" do
    it "carries the `tui-kv` class for grid layout activation" do
      render_inline(described_class.new(rows: [ [ "a", "1" ] ]))

      expect(page).to have_css("dl.tui-kv")
    end
  end
end
