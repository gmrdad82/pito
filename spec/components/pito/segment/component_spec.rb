# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Segment::Component do
  describe "#initialize" do
    it "accepts no arguments (all defaults nil)" do
      comp = described_class.new
      expect(comp).to be_a(described_class)
    end

    it "accepts accent and background" do
      comp = described_class.new(accent: :orange, background: "var(--bg-surface)")
      expect(comp).to be_a(described_class)
    end
  end

  describe "render without accent or background" do
    it "renders the yielded content" do
      node = render_inline(described_class.new) { "hello segment" }
      expect(node.to_html).to include("hello segment")
    end

    it "does not render the bar element" do
      node = render_inline(described_class.new) { "content" }
      expect(node.css(".pito-segment__bar")).to be_empty
    end

    it "uses 22px left padding when no accent" do
      node = render_inline(described_class.new) { "content" }
      content_div = node.css(".pito-segment__content").first
      expect(content_div["style"]).to be_nil
      expect(content_div["class"]).not_to include("pito-segment__content--barred")
    end

    it "does not apply a background style" do
      node = render_inline(described_class.new) { "content" }
      content_div = node.css(".pito-segment__content").first
      expect(content_div["style"]).to be_nil
    end
  end

  describe "render with accent" do
    it "renders the color bar element" do
      node = render_inline(described_class.new(accent: :orange)) { "content" }
      bar = node.css(".pito-segment__bar").first
      expect(bar).not_to be_nil
    end

    it "applies the data-accent attribute" do
      node = render_inline(described_class.new(accent: :orange)) { "content" }
      bar = node.css(".pito-segment__bar").first
      expect(bar["data-accent"]).to eq("orange")
    end

    it "adds the barred modifier to the content wrapper" do
      node = render_inline(described_class.new(accent: :orange)) { "content" }
      content_div = node.css(".pito-segment__content").first
      expect(content_div["class"]).to include("pito-segment__content--barred")
    end

    it "renders the yielded content inside the content wrapper" do
      node = render_inline(described_class.new(accent: :orange)) { "inner text" }
      expect(node.css(".pito-segment__content").text).to include("inner text")
    end
  end

  describe "render with background" do
    it "applies the background to the content wrapper" do
      node = render_inline(described_class.new(background: "var(--bg-surface)")) { "content" }
      content_div = node.css(".pito-segment__content").first
      expect(content_div["style"]).to include("background: var(--bg-surface)")
    end
  end

  describe "render with accent and background together" do
    it "renders bar, applies background, and shows content" do
      node = render_inline(
        described_class.new(accent: :red, background: "var(--bg-surface)")
      ) { "combined" }
      expect(node.css(".pito-segment__bar")).not_to be_empty
      expect(node.css(".pito-segment__content").first["style"]).to include("background: var(--bg-surface)")
      expect(node.css(".pito-segment__content").text).to include("combined")
    end
  end

  describe "outer wrapper" do
    it "has class pito-segment and flex" do
      node = render_inline(described_class.new) { "x" }
      outer = node.css(".pito-segment").first
      expect(outer).not_to be_nil
      expect(outer["class"]).to include("flex")
    end
  end
end
