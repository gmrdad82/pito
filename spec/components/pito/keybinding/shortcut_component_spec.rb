# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Keybinding::ShortcutComponent do
  describe "rendered output" do
    it "renders the keys text, glyph-formatted, in a kbd-shimmer span (bold, pito-blue base + purple band via CSS)" do
      node = render_inline(described_class.new(keys: "ctrl+k"))
      span = node.css("span.pito-kbd-shimmer").first
      expect(span).not_to be_nil
      expect(span.text).to eq("ctrl+k")
    end

    it "renders a single span element (no wrapper)" do
      node = render_inline(described_class.new(keys: "tab"))
      expect(node.css("span").count).to eq(1)
    end

    it "applies the shimmer class with a stable staggered offset bucket" do
      span = render_inline(described_class.new(keys: "ctrl+k")).css("span").first
      expect(span["class"]).to include("pito-kbd-shimmer")
      expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
      again = render_inline(described_class.new(keys: "ctrl+k")).css("span").first
      expect(again["class"]).to eq(span["class"])
    end

    it "always wires the pito--kbd-click controller so the hint is tappable" do
      node = render_inline(described_class.new(keys: "ctrl+k"))
      span = node.css("span").first
      expect(span["data-controller"]).to eq("pito--kbd-click")
      expect(span["data-action"]).to eq("mousedown->pito--kbd-click#hold click->pito--kbd-click#fire")
      expect(span["data-pito--kbd-click-key-value"]).to eq("ctrl+k")
    end

    it "merges data-* attributes from the data hash, concatenating controller/action" do
      node = render_inline(described_class.new(keys: "ctrl+k", data: { "controller" => "pito--example", "action" => "toggle" }))
      span = node.css("span").first
      expect(span["data-controller"]).to eq("pito--kbd-click pito--example")
      expect(span["data-action"]).to eq("mousedown->pito--kbd-click#hold click->pito--kbd-click#fire toggle")
      expect(span["data-pito--kbd-click-key-value"]).to eq("ctrl+k")
    end

    it "routes every key string through Pito::Keybinding::Glyph before rendering" do
      {
        "ctrl+space" => "ctrl+space",
        "m"          => "m",
        "ctrl+/"     => "ctrl+/",
        "ctrl+k"     => "ctrl+k"
      }.each do |keys, glyph|
        node = render_inline(described_class.new(keys: keys))
        expect(node.css("span.pito-kbd-shimmer").text).to eq(glyph)
      end
    end

    it "leaves the data-pito--kbd-click-key-value attribute RAW (unformatted) — the tap-to-fire lookup stays keyed on the semantic shortcut, not its display glyph" do
      node = render_inline(described_class.new(keys: "ctrl+k"))
      span = node.css("span").first
      expect(span["data-pito--kbd-click-key-value"]).to eq("ctrl+k")
      expect(span.text).to eq("ctrl+k")
    end
  end
end
