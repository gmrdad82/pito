# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Tip::Component do
  describe "default rendering" do
    subject(:node) { render_inline(described_class.new(text: "Some tip text")) }

    it "renders the tip text" do
      expect(node.text).to include("Some tip text")
    end

    it "renders the default badge" do
      expect(node.css("span.font-bold.text-yellow").first).to be_present
    end

    it "renders the exclamation mark in orange" do
      expect(node.css("span.text-orange").first.text).to eq("!")
    end

    it "renders the em-dash separator" do
      expect(node.text).to include("—")
    end
  end

  describe "custom badge" do
    subject(:node) do
      render_inline(described_class.new(
        text:              "Not found",
        badge_text:        "404",
        badge_class:       "font-bold text-red",
        exclamation_class: "text-red"
      ))
    end

    it "renders the custom badge text" do
      expect(node.css("span.font-bold.text-red").first.text).to eq("404")
    end

    it "renders the exclamation mark in the custom class" do
      exclamation = node.css("span.text-red").first
      expect(exclamation.text).to eq("!")
    end
  end
end
