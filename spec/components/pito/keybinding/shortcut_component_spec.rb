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

    it "applies no extra data attributes when data is omitted" do
      node = render_inline(described_class.new(keys: "tab"))
      span = node.css("span").first
      data_attrs = span.attributes.keys.select { |k| k.start_with?("data-") }
      expect(data_attrs).to be_empty
    end

    it "applies data-* attributes from the data hash" do
      node = render_inline(described_class.new(keys: "ctrl+k", data: { "controller" => "pito--platform-key", "action" => "toggle" }))
      span = node.css("span").first
      expect(span["data-controller"]).to eq("pito--platform-key")
      expect(span["data-action"]).to eq("toggle")
    end

    it "renders various key strings correctly" do
      [ "shift+tab", "shift+space", "m", "ctrl+/", "ctrl+k" ].each do |keys|
        node = render_inline(described_class.new(keys: keys))
        expect(node.css("span.font-bold.text-yellow").text).to eq(keys)
      end
    end
  end
end
