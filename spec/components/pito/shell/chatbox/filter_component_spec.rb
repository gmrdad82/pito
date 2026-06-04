# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::FilterComponent do
  describe "rendered output" do
    it "renders inside an inline-flex gap-1 wrapper" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@all"))
      wrapper = node.css("span.inline-flex.items-center.gap-1").first
      expect(wrapper).not_to be_nil
    end

    it "renders the shortcut in bold yellow via ShortcutComponent" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@all"))
      yellow = node.css("span.font-bold.text-yellow").first
      expect(yellow).not_to be_nil
      expect(yellow.text).to eq("shift+tab")
    end

    it "renders the value in a text-cyan span" do
      node = render_inline(described_class.new(shortcut: "shift+space", value: "7d"))
      cyan = node.css("span.text-cyan").first
      expect(cyan).not_to be_nil
      expect(cyan.text).to eq("7d")
    end

    it "renders the shortcut before the value" do
      node = render_inline(described_class.new(shortcut: "shift+tab", value: "@sports"))
      spans = node.css("span.inline-flex.items-center.gap-1 > span")
      expect(spans.first["class"]).to include("font-bold")
      expect(spans.first["class"]).to include("text-yellow")
      expect(spans.last["class"]).to include("text-cyan")
    end

    it "renders various shortcut + value combinations" do
      [
        [ "shift+tab", "@gaming" ],
        [ "shift+space", "30d" ],
        [ "shift+space", "1h" ]
      ].each do |shortcut, value|
        node = render_inline(described_class.new(shortcut: shortcut, value: value))
        expect(node.css("span.font-bold.text-yellow").text).to eq(shortcut)
        expect(node.css("span.text-cyan").text).to eq(value)
      end
    end
  end
end
