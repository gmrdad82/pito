# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Segment::Component do
  describe "#initialize" do
    it "accepts no arguments (all defaults nil)" do
      comp = described_class.new
      expect(comp).to be_a(described_class)
    end

    it "accepts border and background" do
      comp = described_class.new(border: "1px solid red", background: "blue")
      expect(comp).to be_a(described_class)
    end
  end

  describe "render without border or background" do
    it "renders the yielded content" do
      node = render_inline(described_class.new) { "hello segment" }
      expect(node.to_html).to include("hello segment")
    end

    it "does not render the color bar element" do
      node = render_inline(described_class.new) { "content" }
      # No bar div when border is nil — only the outer flex wrapper and content div
      bar_divs = node.css("div[style*='width: 4px']")
      expect(bar_divs).to be_empty
    end

    it "uses 22px left padding when no border" do
      node = render_inline(described_class.new) { "content" }
      content_div = node.css("div.flex-1").first
      expect(content_div["style"]).to include("padding: 10px 16px 10px 22px")
    end

    it "does not apply a background style" do
      node = render_inline(described_class.new) { "content" }
      content_div = node.css("div.flex-1").first
      expect(content_div["style"]).not_to include("background:")
    end
  end

  describe "render with border" do
    let(:border_value) { "1px solid var(--accent-orange)" }

    it "renders the color bar element" do
      node = render_inline(described_class.new(border: border_value)) { "content" }
      bar = node.css("div[style*='width: 4px']").first
      expect(bar).not_to be_nil
    end

    it "applies the border value as the bar's background" do
      node = render_inline(described_class.new(border: border_value)) { "content" }
      bar = node.css("div[style*='width: 4px']").first
      expect(bar["style"]).to include(border_value)
    end

    it "uses 12px left padding on the content wrapper when border is present" do
      node = render_inline(described_class.new(border: border_value)) { "content" }
      content_div = node.css("div.flex-1").first
      expect(content_div["style"]).to include("padding: 10px 16px 10px 12px")
    end

    it "renders the yielded content inside the content wrapper" do
      node = render_inline(described_class.new(border: border_value)) { "inner text" }
      expect(node.css("div.flex-1").text).to include("inner text")
    end
  end

  describe "render with background" do
    it "applies the background to the content wrapper" do
      node = render_inline(described_class.new(background: "var(--bg-surface)")) { "content" }
      content_div = node.css("div.flex-1").first
      expect(content_div["style"]).to include("background: var(--bg-surface)")
    end
  end

  describe "render with border and background together" do
    it "renders bar, applies background, and shows content" do
      node = render_inline(
        described_class.new(border: "1px solid red", background: "var(--bg-surface)")
      ) { "combined" }
      expect(node.css("div[style*='width: 4px']")).not_to be_empty
      expect(node.css("div.flex-1").first["style"]).to include("background: var(--bg-surface)")
      expect(node.css("div.flex-1").text).to include("combined")
    end
  end

  describe "outer wrapper" do
    it "has class flex and a bottom margin" do
      node = render_inline(described_class.new) { "x" }
      outer = node.css("div.flex").first
      expect(outer).not_to be_nil
      expect(outer["style"]).to include("margin-bottom: 16px")
    end
  end
end
