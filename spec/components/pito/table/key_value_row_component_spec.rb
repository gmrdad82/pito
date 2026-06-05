# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Table::KeyValueRowComponent do
  describe "default rendering (no wrapper)" do
    subject(:node) { render_inline(described_class.new(key_text: "Resolution", value_text: "1080p")) }

    it "renders a span with default cyan key classes" do
      key_span = node.css("span").first
      expect(key_span["class"]).to include("text-cyan")
      expect(key_span["class"]).to include("whitespace-nowrap")
    end

    it "renders the key text" do
      expect(node.css("span").first.text).to eq("Resolution")
    end

    it "renders the value text in a second span" do
      expect(node.css("span").last.text).to eq("1080p")
    end

    it "renders the value span with text-fg-dim" do
      expect(node.css("span.text-fg-dim").first).not_to be_nil
    end

    it "renders exactly two spans when no wrapper_class" do
      expect(node.css("span").size).to eq(2)
    end
  end

  describe "custom key_class and value_class" do
    it "applies custom key_class to the key span" do
      node = render_inline(described_class.new(
        key_text: "Status", value_text: "ok",
        key_class: "text-fg-dim whitespace-nowrap shrink-0"
      ))
      key_span = node.css("span").first
      expect(key_span["class"]).to include("text-fg-dim")
      expect(key_span["class"]).to include("shrink-0")
    end

    it "applies custom value_class to the value span" do
      node = render_inline(described_class.new(
        key_text: "Token", value_text: "abc123",
        value_class: "text-green break-all"
      ))
      value_span = node.css("span").last
      expect(value_span["class"]).to include("text-green")
      expect(value_span["class"]).to include("break-all")
    end
  end

  describe "wrapper_class" do
    it "wraps both spans in a div when wrapper_class is provided" do
      node = render_inline(described_class.new(
        key_text: "Views", value_text: "1.2M",
        wrapper_class: "flex items-center gap-1"
      ))
      wrapper = node.css("div.flex").first
      expect(wrapper).not_to be_nil
      expect(wrapper["class"]).to include("items-center")
      expect(wrapper["class"]).to include("gap-1")
      expect(wrapper.css("span").size).to eq(2)
    end

    it "does not render a wrapper div when wrapper_class is nil" do
      node = render_inline(described_class.new(key_text: "k", value_text: "v"))
      expect(node.css("div")).to be_empty
    end
  end

  describe "keybinding table row style (w-44 key, no wrapper)" do
    it "accepts w-44 shrink-0 key class and renders correctly" do
      node = render_inline(described_class.new(
        key_text: "/help",
        value_text: "Show help",
        key_class: "text-cyan whitespace-nowrap shrink-0 w-44"
      ))
      key_span = node.css("span").first
      expect(key_span["class"]).to include("w-44")
      expect(node.css("span").last.text).to eq("Show help")
    end
  end
end
