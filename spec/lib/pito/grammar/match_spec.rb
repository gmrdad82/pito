# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Match do
  describe "construction with defaults" do
    subject(:match) { described_class.new(namespace: :slash) }

    it "stores the required namespace" do
      expect(match.namespace).to eq(:slash)
    end

    it "defaults name to nil" do
      expect(match.name).to be_nil
    end

    it "defaults values to {}" do
      expect(match.values).to eq({})
    end

    it "defaults kwargs to {}" do
      expect(match.kwargs).to eq({})
    end

    it "defaults leftovers to []" do
      expect(match.leftovers).to eq([])
    end

    it "defaults unknowns to []" do
      expect(match.unknowns).to eq([])
    end

    it "defaults corrections to {}" do
      expect(match.corrections).to eq({})
    end

    it "defaults confidence to 0.0" do
      expect(match.confidence).to eq(0.0)
    end

    it "defaults matched to false" do
      expect(match.matched).to be(false)
    end
  end

  describe "construction with all fields" do
    subject(:match) do
      described_class.new(
        namespace:  :chat,
        name:       :list,
        values:     { genre: "RPG" },
        kwargs:     { limit: "10" },
        leftovers:  [ "extra" ],
        unknowns:   [ "unknown_word" ],
        confidence: 0.85,
        matched:    true
      )
    end

    it "stores namespace" do
      expect(match.namespace).to eq(:chat)
    end

    it "stores name" do
      expect(match.name).to eq(:list)
    end

    it "stores values" do
      expect(match.values).to eq({ genre: "RPG" })
    end

    it "stores kwargs" do
      expect(match.kwargs).to eq({ limit: "10" })
    end

    it "stores leftovers" do
      expect(match.leftovers).to eq([ "extra" ])
    end

    it "stores unknowns" do
      expect(match.unknowns).to eq([ "unknown_word" ])
    end

    it "stores confidence" do
      expect(match.confidence).to eq(0.85)
    end

    it "stores matched" do
      expect(match.matched).to be(true)
    end
  end

  describe "#matched?" do
    it "returns false when matched is false" do
      match = described_class.new(namespace: :slash, matched: false)
      expect(match.matched?).to be(false)
    end

    it "returns true when matched is true" do
      match = described_class.new(namespace: :slash, matched: true)
      expect(match.matched?).to be(true)
    end

    it "defaults to false" do
      match = described_class.new(namespace: :hashtag)
      expect(match.matched?).to be(false)
    end
  end

  describe "repeatable slot values" do
    it "accepts an Array<String> as a slot value" do
      match = described_class.new(namespace: :slash, values: { tags: [ "rpg", "shooter" ] })
      expect(match.values[:tags]).to eq([ "rpg", "shooter" ])
    end
  end
end
