# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Cursor::Component do
  describe "#initialize" do
    it "uses default char '/' when not specified" do
      comp = described_class.new
      expect(comp.ghost?).to be false
    end

    it "accepts custom char" do
      comp = described_class.new(char: "|")
      expect(comp).to be_a(described_class)
    end

    it "defaults ghost to false" do
      comp = described_class.new
      expect(comp.ghost?).to be false
    end

    it "sets ghost to true when passed" do
      comp = described_class.new(ghost: true)
      expect(comp.ghost?).to be true
    end
  end

  describe "#ghost?" do
    it "returns false by default" do
      expect(described_class.new.ghost?).to be false
    end

    it "returns true when ghost: true" do
      expect(described_class.new(ghost: true).ghost?).to be true
    end

    it "returns false when ghost: false explicitly" do
      expect(described_class.new(ghost: false).ghost?).to be false
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

    it "does not have the ghost CSS class" do
      expect(node.css("span.pito-cursor--ghost")).to be_empty
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

  describe "rendered output — ghost mode" do
    subject(:node) { render_inline(described_class.new(ghost: true)) }

    it "renders a span with the ghost class" do
      expect(node.css("span.pito-cursor--ghost")).not_to be_empty
    end

    it "renders the default '/' character" do
      expect(node.text).to include("/")
    end
  end

  describe "rendered output — ghost with custom char" do
    it "renders the custom char inside the ghost span" do
      node = render_inline(described_class.new(char: "X", ghost: true))
      ghost_span = node.css("span.pito-cursor--ghost").first
      expect(ghost_span).not_to be_nil
      expect(ghost_span.text).to include("X")
    end
  end

  describe "rendered output — custom color (solid)" do
    it "applies the color to the span style" do
      node = render_inline(described_class.new(color: "var(--accent-cyan)"))
      span = node.css("span").first
      expect(span["style"]).to include("var(--accent-cyan)")
    end
  end

  describe "rendered output — custom color (ghost)" do
    it "sets the --cursor-color CSS variable on the ghost span" do
      node = render_inline(described_class.new(color: "var(--accent-orange)", ghost: true))
      span = node.css("span.pito-cursor--ghost").first
      expect(span["style"]).to include("var(--accent-orange)")
    end
  end
end
