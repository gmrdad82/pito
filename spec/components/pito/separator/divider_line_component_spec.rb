# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Separator::DividerLineComponent do
  describe "bordered block mode (default)" do
    it "renders a div with mt-1.5 border-t border-line-default pt-1.5 by default" do
      node = render_inline(described_class.new) { "content" }
      div = node.css("div").first
      expect(div["class"]).to include("mt-1.5")
      expect(div["class"]).to include("border-t")
      expect(div["class"]).to include("border-line-default")
      expect(div["class"]).to include("pt-1.5")
    end

    it "renders content inside the wrapper" do
      node = render_inline(described_class.new) { "inner text" }
      expect(node.text).to include("inner text")
    end

    it "uses border-line-faded when tone: :faded" do
      node = render_inline(described_class.new(tone: :faded)) { "x" }
      div = node.css("div").first
      expect(div["class"]).to include("border-line-faded")
      expect(div["class"]).not_to include("border-line-default")
    end

    it "uses custom spacing when spacing: '2'" do
      node = render_inline(described_class.new(spacing: "2")) { "x" }
      div = node.css("div").first
      expect(div["class"]).to include("mt-2")
      expect(div["class"]).to include("pt-2")
      expect(div["class"]).not_to include("mt-1.5")
    end

    it "appends extra_classes to the wrapper" do
      node = render_inline(described_class.new(extra_classes: "font-mono break-all")) { "x" }
      div = node.css("div").first
      expect(div["class"]).to include("font-mono")
      expect(div["class"]).to include("break-all")
    end

    it "does not render a hairline h-px div in block mode" do
      node = render_inline(described_class.new) { "content" }
      expect(node.css("div.h-px")).to be_empty
    end
  end

  describe "hairline mode (hairline: true)" do
    it "renders a div.h-px.bg-line-default with no content" do
      node = render_inline(described_class.new(hairline: true))
      div = node.css("div").first
      expect(div["class"]).to include("h-px")
      expect(div["class"]).to include("bg-line-default")
    end

    it "does not include border-t in hairline mode" do
      node = render_inline(described_class.new(hairline: true))
      div = node.css("div").first
      expect(div["class"]).not_to include("border-t")
    end

    it "adds my-{n} class when my: is provided" do
      node = render_inline(described_class.new(hairline: true, my: "2"))
      div = node.css("div").first
      expect(div["class"]).to include("my-2")
    end

    it "omits my class when my: is not provided" do
      node = render_inline(described_class.new(hairline: true))
      div = node.css("div").first
      expect(div["class"]).not_to include("my-")
    end

    it "uses bg-line-faded when tone: :faded (the fainter hairline)" do
      node = render_inline(described_class.new(hairline: true, tone: :faded))
      div = node.css("div").first
      expect(div["class"]).to include("bg-line-faded")
      expect(div["class"]).not_to include("bg-line-default")
    end
  end

  describe "tone validation" do
    it "falls back to border-line-default for unknown tone" do
      node = render_inline(described_class.new(tone: :unknown)) { "x" }
      div = node.css("div").first
      expect(div["class"]).to include("border-line-default")
    end
  end
end
