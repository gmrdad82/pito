# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Keybinding::HintComponent do
  describe "shortcut span" do
    it "renders the shortcut in bold yellow" do
      node = render_inline(described_class.new(shortcut: "ctrl+|", description: "to expand"))
      expect(node.css("span.font-bold.text-yellow").text).to include("ctrl+|")
    end

    it "adds data-* attributes from shortcut_data" do
      node = render_inline(described_class.new(
        shortcut: "ctrl+k", description: "commands",
        shortcut_data: { action: "toggle", target: "audio" }
      ))
      hint_span = node.css("span.font-bold.text-yellow").first
      expect(hint_span["data-action"]).to eq("toggle")
      expect(hint_span["data-target"]).to eq("audio")
    end
  end

  describe "description span" do
    it "renders the description in dim text with ml-2" do
      node = render_inline(described_class.new(shortcut: "ctrl+|", description: "to expand"))
      desc_span = node.css("span.text-fg-dim").first
      expect(desc_span.text).to include("to expand")
      expect(desc_span["class"]).to include("ml-2")
    end

    it "sets id when description_id is given" do
      node = render_inline(described_class.new(
        shortcut: "tab", description: "channels", description_id: "pito-tab-label"
      ))
      expect(node.css("span#pito-tab-label").text).to include("channels")
    end

    it "adds data-* attributes from description_data onto the description span" do
      node = render_inline(described_class.new(
        shortcut: "ctrl+|", description: "to expand",
        description_data: { "pito--expand-target" => "hintLabel" }
      ))
      desc_span = node.css("span.text-fg-dim").first
      expect(desc_span["data-pito--expand-target"]).to eq("hintLabel")
    end
  end
end
