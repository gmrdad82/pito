# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationSpinnerComponent do
  let(:frames_json) { %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].to_json }
  let(:word)        { "Disconnecting" }

  subject(:node) { render_inline(described_class.new(frames_json:, word:)) }

  describe "outer container" do
    it "renders div.pito-thinking" do
      expect(node.css("div.pito-thinking")).not_to be_empty
    end

    it "renders div.mb-1" do
      expect(node.css("div.mb-1")).not_to be_empty
    end

    it "div.pito-thinking also carries the mb-1 class" do
      div = node.css("div.pito-thinking").first
      expect(div["class"]).to include("mb-1")
    end
  end

  describe "braille span" do
    it "has data-controller='pito--thinking'" do
      braille = node.css("[data-controller='pito--thinking']").first
      expect(braille).not_to be_nil
    end

    it "has data-pito--thinking-frames-value equal to frames_json" do
      braille = node.css("[data-controller='pito--thinking']").first
      expect(braille["data-pito--thinking-frames-value"]).to eq(frames_json)
    end

    it "has data-pito--thinking-target='braille'" do
      expect(node.css("[data-pito--thinking-target='braille']")).not_to be_empty
    end

    it "braille target and controller are on the same element" do
      el = node.css("[data-pito--thinking-target='braille']").first
      expect(el["data-controller"]).to eq("pito--thinking")
    end
  end

  describe "word span" do
    it "contains the word text" do
      expect(node.text).to include(word)
    end

    it "appends '…' after the word" do
      expect(node.text).to include("#{word}…")
    end

    it "has pito-shimmer class on the word span" do
      shimmer = node.css(".pito-thinking__word.pito-shimmer").first
      expect(shimmer).not_to be_nil
      expect(shimmer.text).to include(word)
    end
  end

  describe "with a different word" do
    subject(:node) { render_inline(described_class.new(frames_json:, word: "Cancelling")) }

    it "renders the new word" do
      expect(node.css(".pito-thinking__word").first.text).to include("Cancelling")
    end

    it "still appends '…'" do
      expect(node.text).to include("Cancelling…")
    end
  end
end
