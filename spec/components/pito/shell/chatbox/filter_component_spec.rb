# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::FilterComponent do
  describe "rendered output" do
    it "renders inside an inline-flex gap-2 wrapper" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@all"))
      wrapper = node.css("span.inline-flex.items-center.gap-2").first
      expect(wrapper).not_to be_nil
    end

    it "renders the shortcut in bold yellow via ShortcutComponent" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@all"))
      yellow = node.css("span.font-bold.text-yellow").first
      expect(yellow).not_to be_nil
      expect(yellow.text).to eq("shift+tab")
    end

    it "renders the value in a shimmer span" do
      node = render_inline(described_class.new(shortcut: "shift+space", value: "7d"))
      shimmer = node.css("span.pito-token-shimmer").first
      expect(shimmer).not_to be_nil
      expect(shimmer.text).to eq("7d")
    end

    it "renders the shortcut before the value" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@sports"))
      spans = node.css("span.inline-flex.items-center.gap-2 > span")
      expect(spans.first["class"]).to include("font-bold")
      expect(spans.first["class"]).to include("text-yellow")
      expect(spans.last["class"]).to include("pito-token-shimmer")
    end

    it "renders various shortcut + value combinations with the shimmer" do
      [
        [ "shift+tab", "@gaming" ],
        [ "shift+space", "30d" ],
        [ "shift+space", "1h" ]
      ].each do |shortcut, value|
        node = render_inline(described_class.new(shortcut: shortcut, value: value))
        expect(node.css("span.font-bold.text-yellow").text).to eq(shortcut)
        expect(node.css("span.pito-token-shimmer").text).to eq(value)
      end
    end
  end
end
