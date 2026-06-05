# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Section::SectionHeaderComponent do
  describe "default rendering" do
    subject(:node) { render_inline(described_class.new(text: "GENERAL")) }

    it "renders a div with font-bold" do
      div = node.css("div").first
      expect(div).not_to be_nil
      expect(div["class"]).to include("font-bold")
    end

    it "renders text-yellow by default" do
      div = node.css("div").first
      expect(div["class"]).to include("text-yellow")
    end

    it "renders mb-1 by default" do
      div = node.css("div").first
      expect(div["class"]).to include("mb-1")
    end

    it "renders the title text" do
      expect(node.text.strip).to eq("GENERAL")
    end

    it "does not add any px class by default" do
      div = node.css("div").first
      expect(div["class"]).not_to include("px-")
    end
  end

  describe "color: :orange" do
    it "renders text-orange instead of text-yellow" do
      node = render_inline(described_class.new(text: "Recent", color: :orange))
      div = node.css("div").first
      expect(div["class"]).to include("text-orange")
      expect(div["class"]).not_to include("text-yellow")
    end
  end

  describe "px: option" do
    it "adds px-[7px] class when px: '[7px]'" do
      node = render_inline(described_class.new(text: "Commands", px: "[7px]"))
      div = node.css("div").first
      expect(div["class"]).to include("px-[7px]")
    end
  end

  describe "extra_attrs" do
    it "passes extra HTML attributes to the div" do
      node = render_inline(described_class.new(
        text: "Section",
        extra_attrs: { "data-pito--command-palette-target" => "sectionTitle" }
      ))
      div = node.css("div").first
      expect(div["data-pito--command-palette-target"]).to eq("sectionTitle")
    end
  end

  describe "mb: option" do
    it "renders mb-2 when mb: '2'" do
      node = render_inline(described_class.new(text: "Title", mb: "2"))
      div = node.css("div").first
      expect(div["class"]).to include("mb-2")
      expect(div["class"]).not_to include("mb-1 ")
    end
  end

  describe "all call site combinations" do
    it "sidebar section_component style: orange, no px" do
      node = render_inline(described_class.new(text: "Overview", color: :orange))
      div = node.css("div").first
      expect(div["class"]).to match(/\btext-orange\b/)
      expect(div["class"]).to match(/\bfont-bold\b/)
      expect(div["class"]).to match(/\bmb-1\b/)
    end

    it "ctrl_k section_component style: yellow, px-[7px]" do
      node = render_inline(described_class.new(text: "Commands", color: :yellow, px: "[7px]"))
      div = node.css("div").first
      expect(div["class"]).to match(/\btext-yellow\b/)
      expect(div["class"]).to include("px-[7px]")
    end

    it "keybinding table_component style: yellow, no px" do
      node = render_inline(described_class.new(text: "CONFIG"))
      div = node.css("div").first
      expect(div["class"]).to match(/\btext-yellow\b/)
      expect(div["class"]).not_to include("px-")
    end
  end
end
