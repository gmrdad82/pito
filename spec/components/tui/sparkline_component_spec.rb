require "rails_helper"

# Beta 4 Phase F2 — Tui::SparklineComponent.
#
# Pure presentational primitive that maps a numeric series onto a row
# of Unicode block characters (U+2581..U+2587). The component is
# stateless; spec coverage targets the projection math + the
# edge-case branches (empty input, all-zero series, single value,
# clamping) explicitly called out in the deferred-specs playbook.
RSpec.describe Tui::SparklineComponent, type: :component do
  describe "BLOCKS constant" do
    it "exposes the 7-block palette `▁▂▃▄▅▆▇`" do
      expect(described_class::BLOCKS).to eq(%w[▁ ▂ ▃ ▄ ▅ ▆ ▇])
    end
  end

  describe "wrapper element" do
    it "renders inside a single `<span class=\"tui-sparkline\">`" do
      render_inline(described_class.new(values: [ 1, 2, 3 ]))

      expect(page).to have_css("span.tui-sparkline", count: 1)
    end
  end

  describe "#rendered (block projection)" do
    it "returns the empty string when the values array is empty" do
      component = described_class.new(values: [])

      expect(component.rendered).to eq("")
    end

    it "renders a flat row of `▁` (lowest block) for an all-zero series" do
      component = described_class.new(values: [ 0, 0, 0, 0 ])

      expect(component.rendered).to eq("▁▁▁▁")
    end

    it "matches the input length on an all-zero series" do
      component = described_class.new(values: [ 0 ] * 12)

      expect(component.rendered.chars.length).to eq(12)
    end

    it "renders the top block `▇` for a single-value series (own max)" do
      component = described_class.new(values: [ 42 ])

      expect(component.rendered).to eq("▇")
    end

    it "maps a value of zero against a positive max to the lowest block" do
      component = described_class.new(values: [ 0, 100 ])

      expect(component.rendered.chars.first).to eq("▁")
    end

    it "maps a value equal to max to the highest block" do
      component = described_class.new(values: [ 0, 100 ])

      expect(component.rendered.chars.last).to eq("▇")
    end

    it "picks block by `(v / max) * 6` rounded" do
      # max = 6, so each unit maps to one block index after rounding.
      component = described_class.new(values: [ 0, 1, 2, 3, 4, 5, 6 ])

      expect(component.rendered).to eq("▁▂▃▄▅▆▇")
    end

    it "accepts float values without raising" do
      component = described_class.new(values: [ 0.5, 1.2, 3.7 ])

      expect { component.rendered }.not_to raise_error
      expect(component.rendered.chars.length).to eq(3)
    end

    it "accepts negative values without raising (clamp keeps output well-formed)" do
      component = described_class.new(values: [ -5, 5, 10 ])

      expect { component.rendered }.not_to raise_error
      expect(component.rendered.chars.length).to eq(3)
    end

    it "every output character belongs to the BLOCKS palette" do
      component = described_class.new(values: [ 7, 2, 9, 3, 1, 8 ])

      component.rendered.chars.each do |ch|
        expect(described_class::BLOCKS).to include(ch)
      end
    end
  end

  describe "input coercion" do
    it "coerces enumerable input via `.to_a`" do
      component = described_class.new(values: (1..5))

      expect(component.values).to eq([ 1, 2, 3, 4, 5 ])
      expect(component.rendered.chars.length).to eq(5)
    end
  end

  describe "render output" do
    it "renders the block string inside the wrapper span" do
      render_inline(described_class.new(values: [ 1, 2, 3 ]))

      expect(page).to have_css("span.tui-sparkline", text: "▃▅▇")
    end

    it "renders an empty span when no values are passed" do
      render_inline(described_class.new(values: []))

      expect(page).to have_css("span.tui-sparkline", text: "")
    end
  end
end
