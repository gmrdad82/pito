# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Keybinding::ShortcutComponent do
  describe "rendered output" do
    it "renders the keys text in a bold yellow span" do
      node = render_inline(described_class.new(keys: "ctrl+k"))
      span = node.css("span.font-bold.text-yellow").first
      expect(span).not_to be_nil
      expect(span.text).to eq("ctrl+k")
    end

    it "renders a single span element (no wrapper)" do
      node = render_inline(described_class.new(keys: "tab"))
      expect(node.css("span").count).to eq(1)
    end

    it "applies the shimmer class with a stable staggered offset bucket" do
      span = render_inline(described_class.new(keys: "ctrl+k")).css("span").first
      expect(span["class"]).to include("pito-action-shimmer")
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
      node = render_inline(described_class.new(keys: "ctrl+k", data: { "controller" => "pito--platform-key", "action" => "toggle" }))
      span = node.css("span").first
      expect(span["data-controller"]).to eq("pito--kbd-click pito--platform-key")
      expect(span["data-action"]).to eq("mousedown->pito--kbd-click#hold click->pito--kbd-click#fire toggle")
      expect(span["data-pito--kbd-click-key-value"]).to eq("ctrl+k")
    end

    it "renders various key strings correctly" do
      [ "shift+tab", "shift+space", "m", "ctrl+/", "ctrl+k" ].each do |keys|
        node = render_inline(described_class.new(keys: keys))
        expect(node.css("span.font-bold.text-yellow").text).to eq(keys)
      end
    end
  end
end
