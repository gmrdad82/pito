require "rails_helper"

# Beta 4 Phase F2 — Tui::ProgressBarComponent.
#
# Static ASCII progress bar (▓ filled / ░ empty) wrapped in literal
# `[ ]` brackets with a `N/M` counter label. Pure presentational
# primitive; coverage targets the math (filled_count, clamp, default
# width), the bracket grammar in the template, and the div-by-zero
# guards spelled out in the deferred-specs playbook.
RSpec.describe Tui::ProgressBarComponent, type: :component do
  describe "default width" do
    it "defaults to 10 cells" do
      component = described_class.new(current: 5, total: 10)

      expect(component.width).to eq(10)
    end

    it "honors a custom `width:` arg" do
      component = described_class.new(current: 5, total: 10, width: 20)

      expect(component.width).to eq(20)
    end
  end

  describe "#filled_count" do
    it "is half the width when current is half of total" do
      component = described_class.new(current: 5, total: 10, width: 10)

      expect(component.filled_count).to eq(5)
    end

    it "is zero when current is zero" do
      component = described_class.new(current: 0, total: 10, width: 10)

      expect(component.filled_count).to eq(0)
    end

    it "equals width when current equals total" do
      component = described_class.new(current: 10, total: 10, width: 10)

      expect(component.filled_count).to eq(10)
    end

    it "is zero when total is zero (no division-by-zero)" do
      component = described_class.new(current: 5, total: 0, width: 10)

      expect(component.filled_count).to eq(0)
    end

    it "is zero when total is negative" do
      component = described_class.new(current: 5, total: -1, width: 10)

      expect(component.filled_count).to eq(0)
    end

    it "clamps to width when current > total (no overflow)" do
      component = described_class.new(current: 99, total: 10, width: 10)

      expect(component.filled_count).to eq(10)
    end

    it "clamps to zero when current is negative" do
      component = described_class.new(current: -5, total: 10, width: 10)

      expect(component.filled_count).to eq(0)
    end
  end

  describe "#rendered (bar glyphs)" do
    it "renders width glyphs total" do
      component = described_class.new(current: 3, total: 10, width: 10)

      expect(component.rendered.chars.length).to eq(10)
    end

    it "renders ▓ for filled cells and ░ for empty cells" do
      component = described_class.new(current: 3, total: 10, width: 10)

      expect(component.rendered).to eq("▓▓▓░░░░░░░")
    end

    it "renders all-empty when total is zero" do
      component = described_class.new(current: 0, total: 0, width: 10)

      expect(component.rendered).to eq("░░░░░░░░░░")
    end

    it "renders all-filled when current equals total" do
      component = described_class.new(current: 10, total: 10, width: 10)

      expect(component.rendered).to eq("▓▓▓▓▓▓▓▓▓▓")
    end

    it "respects custom width" do
      component = described_class.new(current: 2, total: 4, width: 4)

      expect(component.rendered).to eq("▓▓░░")
    end
  end

  describe "#label" do
    it "formats as `current/total`" do
      component = described_class.new(current: 3, total: 10)

      expect(component.label).to eq("3/10")
    end

    it "renders `0/0` for the empty-edge case" do
      component = described_class.new(current: 0, total: 0)

      expect(component.label).to eq("0/0")
    end

    it "uses the coerced (clamped-to-int) values, not raw" do
      component = described_class.new(current: 3.9, total: 10.1)

      expect(component.label).to eq("3/10")
    end
  end

  describe "input coercion" do
    it "coerces current via `.to_i`" do
      component = described_class.new(current: "5", total: 10)

      expect(component.current).to eq(5)
    end

    it "coerces total via `.to_i`" do
      component = described_class.new(current: 5, total: "10")

      expect(component.total).to eq(10)
    end

    it "coerces width via `.to_i`" do
      component = described_class.new(current: 5, total: 10, width: "20")

      expect(component.width).to eq(20)
    end
  end

  describe "render output (template grammar)" do
    it "wraps the bar in literal `[ ]` brackets per pito bracketed grammar" do
      render_inline(described_class.new(current: 3, total: 10))

      expect(page).to have_css(".tui-progress", text: "[▓▓▓░░░░░░░]")
    end

    it "renders the label outside the brackets in a `.tui-progress__label` span" do
      render_inline(described_class.new(current: 3, total: 10))

      expect(page).to have_css(".tui-progress__label", text: "3/10")
    end

    it "renders the bar inside a `.tui-progress__bar` span" do
      render_inline(described_class.new(current: 5, total: 10))

      expect(page).to have_css(".tui-progress__bar")
    end

    it "wraps everything in a single `.tui-progress` root" do
      render_inline(described_class.new(current: 5, total: 10))

      expect(page).to have_css("span.tui-progress", count: 1)
    end
  end
end
