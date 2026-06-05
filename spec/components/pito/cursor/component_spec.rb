# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Cursor::Component do
  describe "#initialize" do
    it "uses default char '/' when not specified" do
      comp = described_class.new
      expect(comp).to be_a(described_class)
    end

    it "accepts custom char" do
      comp = described_class.new(char: "|")
      expect(comp).to be_a(described_class)
    end
  end

  describe "rendered output — default (solid) cursor" do
    subject(:node) { render_inline(described_class.new) }

    it "renders the default '/' character" do
      expect(node.text).to include("/")
    end

    it "renders a span element" do
      expect(node.css("span")).not_to be_empty
    end

    it "renders a span with the pito-cursor class" do
      expect(node.css("span.pito-cursor")).not_to be_empty
    end
  end

  describe "rendered output — custom char" do
    it "renders the custom character" do
      node = render_inline(described_class.new(char: "|"))
      expect(node.text).to include("|")
    end

    it "renders a different custom character" do
      node = render_inline(described_class.new(char: "▮"))
      expect(node.text).to include("▮")
    end
  end

  describe "rendered output — custom color (solid)" do
    it "applies the color to the span style" do
      node = render_inline(described_class.new(color: "var(--accent-cyan)"))
      span = node.css("span").first
      expect(span["style"]).to include("var(--accent-cyan)")
    end
  end
end
