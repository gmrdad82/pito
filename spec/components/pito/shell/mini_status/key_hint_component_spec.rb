# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::KeyHintComponent do
  describe "hint span" do
    it "renders the hint text in a bold yellow span" do
      node = render_inline(described_class.new(hint: "ctrl+k", label: "commands"))
      expect(node.css("span.font-bold.text-yellow").text).to include("ctrl+k")
    end

    it "adds data-* attributes from hint_data onto the hint span" do
      node = render_inline(described_class.new(hint: "ctrl+m", label: "mute", hint_data: { action: "toggle", target: "audio" }))
      hint_span = node.css("span.font-bold.text-yellow").first
      expect(hint_span["data-action"]).to eq("toggle")
      expect(hint_span["data-target"]).to eq("audio")
    end

    it "renders hint span with no data attributes when hint_data is omitted" do
      node = render_inline(described_class.new(hint: "tab", label: "channels"))
      hint_span = node.css("span.font-bold.text-yellow").first
      expect(hint_span.attributes.keys).not_to include(a_string_starting_with("data-"))
    end
  end

  describe "label span" do
    it "renders the label text in a dim span" do
      node = render_inline(described_class.new(hint: "ctrl+k", label: "commands"))
      expect(node.css("span.text-fg-dim").text).to include("commands")
    end

    it "sets the id attribute on the label span when label_id is given" do
      node = render_inline(described_class.new(hint: "ctrl+m", label: "mute", label_id: "pito-audio-label"))
      label_span = node.css("span#pito-audio-label").first
      expect(label_span).not_to be_nil
      expect(label_span.text).to include("mute")
    end

    it "renders label span without an id when label_id is omitted" do
      node = render_inline(described_class.new(hint: "ctrl+k", label: "commands"))
      label_span = node.css("span.text-fg-dim").first
      expect(label_span["id"]).to be_nil
    end
  end

  describe "without optional params" do
    it "renders successfully with only hint and label" do
      node = render_inline(described_class.new(hint: "tab", label: "channels"))
      expect(node.css("span.font-bold.text-yellow").text).to include("tab")
      expect(node.css("span.text-fg-dim").text).to include("channels")
    end
  end
end
