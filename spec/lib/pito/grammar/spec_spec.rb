# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Spec do
  let(:genre_slot) { Pito::Grammar::Slot.new(name: :genre, kind: :enum, source: :genres) }
  let(:code_slot)  { Pito::Grammar::Slot.new(name: :code,  kind: :literal) }

  describe "construction with all fields" do
    it "stores every field" do
      spec = described_class.new(
        namespace: :slash,
        name: :list,
        aliases: [ :ls ],
        slots: [ genre_slot ],
        description_key: "commands.list.description",
        auth: :authenticated_only
      )

      expect(spec.namespace).to eq(:slash)
      expect(spec.name).to eq(:list)
      expect(spec.aliases).to eq([ :ls ])
      expect(spec.slots).to eq([ genre_slot ])
      expect(spec.description_key).to eq("commands.list.description")
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  describe "defaults for optional fields" do
    subject(:spec) { described_class.new(namespace: :chat, name: :add) }

    it "defaults aliases to []" do
      expect(spec.aliases).to eq([])
    end

    it "defaults slots to []" do
      expect(spec.slots).to eq([])
    end

    it "defaults description_key to nil" do
      expect(spec.description_key).to be_nil
    end

    it "defaults auth to :any" do
      expect(spec.auth).to eq(:any)
    end
  end

  describe "#names" do
    it "returns [name] when there are no aliases" do
      spec = described_class.new(namespace: :slash, name: :help)
      expect(spec.names).to eq([ :help ])
    end

    it "includes aliases after the canonical name" do
      spec = described_class.new(namespace: :slash, name: :list, aliases: [ :ls, :l ])
      expect(spec.names).to eq([ :list, :ls, :l ])
    end
  end

  describe "#slot" do
    subject(:spec) do
      described_class.new(namespace: :hashtag, name: :search, slots: [ genre_slot, code_slot ])
    end

    it "returns the matching slot by name" do
      expect(spec.slot(:genre)).to eq(genre_slot)
      expect(spec.slot(:code)).to eq(code_slot)
    end

    it "returns nil for an unknown slot name" do
      expect(spec.slot(:nonexistent)).to be_nil
    end
  end
end
