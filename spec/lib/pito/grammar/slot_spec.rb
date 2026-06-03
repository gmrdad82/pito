# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Slot do
  describe "construction with all fields" do
    it "stores every field" do
      slot = described_class.new(
        name: :genre,
        kind: :enum,
        source: :genres,
        optional: true,
        repeatable: true,
        synonyms: [ :category ],
        introducer: :for
      )

      expect(slot.name).to eq(:genre)
      expect(slot.kind).to eq(:enum)
      expect(slot.source).to eq(:genres)
      expect(slot.optional).to be(true)
      expect(slot.repeatable).to be(true)
      expect(slot.synonyms).to eq([ :category ])
      expect(slot.introducer).to eq(:for)
    end
  end

  describe "defaults for optional fields" do
    subject(:slot) { described_class.new(name: :code, kind: :literal) }

    it "defaults source to nil" do
      expect(slot.source).to be_nil
    end

    it "defaults optional to false" do
      expect(slot.optional).to be(false)
    end

    it "defaults repeatable to false" do
      expect(slot.repeatable).to be(false)
    end

    it "defaults synonyms to []" do
      expect(slot.synonyms).to eq([])
    end

    it "defaults introducer to nil" do
      expect(slot.introducer).to be_nil
    end
  end

  describe "#optional?" do
    it "returns true when optional is true" do
      slot = described_class.new(name: :provider, kind: :enum, optional: true)
      expect(slot.optional?).to be(true)
    end

    it "returns false when optional is false" do
      slot = described_class.new(name: :provider, kind: :enum, optional: false)
      expect(slot.optional?).to be(false)
    end
  end

  describe "#repeatable?" do
    it "returns true when repeatable is true" do
      slot = described_class.new(name: :tag, kind: :free, repeatable: true)
      expect(slot.repeatable?).to be(true)
    end

    it "returns false when repeatable is false" do
      slot = described_class.new(name: :tag, kind: :free, repeatable: false)
      expect(slot.repeatable?).to be(false)
    end
  end
end
