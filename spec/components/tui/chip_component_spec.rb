require "rails_helper"

RSpec.describe Tui::ChipComponent, type: :component do
  describe "rendering" do
    it "wraps the label in `[ ]` brackets" do
      render_inline(described_class.new(label: "active"))

      expect(page).to have_css(".tui-chip", text: "[active]")
    end

    it "stringifies non-string labels" do
      render_inline(described_class.new(label: :ip))

      expect(page).to have_css(".tui-chip", text: "[ip]")
    end

    it "applies the neutral variant class by default" do
      render_inline(described_class.new(label: "ip"))

      expect(page).to have_css(".tui-chip.tui-chip--neutral")
    end
  end

  describe "variants" do
    Tui::ChipComponent::VARIANTS.each do |variant|
      it "renders the #{variant.inspect} variant with `.tui-chip--#{variant}` on the root span" do
        render_inline(described_class.new(label: "tag", variant: variant))

        expect(page).to have_css("span.tui-chip.tui-chip--#{variant}", text: "[tag]")
      end
    end

    it "raises ArgumentError when given an unknown variant" do
      expect {
        described_class.new(label: "tag", variant: :nope)
      }.to raise_error(ArgumentError, /unknown variant nope/)
    end

    it "exposes the locked set of 6 variants" do
      expect(described_class::VARIANTS).to match_array(%i[neutral info success warn danger current])
    end

    it "accepts string variant input and coerces via to_sym" do
      render_inline(described_class.new(label: "ok", variant: "success"))

      expect(page).to have_css(".tui-chip.tui-chip--success", text: "[ok]")
    end
  end

  describe "css_class helper" do
    it "returns both the base + variant classes" do
      component = described_class.new(label: "x", variant: :danger)

      expect(component.css_class).to eq("tui-chip tui-chip--danger")
    end
  end
end
