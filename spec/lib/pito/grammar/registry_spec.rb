# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Registry do
  before { described_class.reset! }
  after  { described_class.reset! }

  let(:spec_a) do
    Pito::Grammar::Spec.new(
      namespace: :slash,
      name:      :list,
      aliases:   [ :ls, :show ]
    )
  end

  let(:spec_b) do
    Pito::Grammar::Spec.new(
      namespace: :slash,
      name:      :add
    )
  end

  let(:chat_spec) do
    Pito::Grammar::Spec.new(
      namespace: :chat,
      name:      :search
    )
  end

  let(:vocab_genres) do
    Pito::Grammar::Vocabulary.define(
      name:      :genres,
      canonical: [ "Shooter", "RPG" ],
      synonyms:  { "fps" => "Shooter" }
    )
  end

  let(:vocab_platforms) do
    Pito::Grammar::Vocabulary.define(
      name:      :platforms,
      canonical: [ "PC", "PlayStation" ]
    )
  end

  describe ".register_spec / .spec" do
    it "retrieves a registered spec by canonical name" do
      described_class.register_spec(spec_a)
      expect(described_class.spec(namespace: :slash, name: :list)).to eq(spec_a)
    end

    it "returns nil for an unregistered name" do
      expect(described_class.spec(namespace: :slash, name: :nonexistent)).to be_nil
    end

    it "returns nil for a different namespace" do
      described_class.register_spec(spec_a)
      expect(described_class.spec(namespace: :chat, name: :list)).to be_nil
    end
  end

  describe ".specs_for_alias" do
    before { described_class.register_spec(spec_a) }

    it "finds the spec by its canonical name" do
      expect(described_class.specs_for_alias(namespace: :slash, token: :list)).to eq(spec_a)
    end

    it "finds the spec by an alias (Symbol)" do
      expect(described_class.specs_for_alias(namespace: :slash, token: :ls)).to eq(spec_a)
    end

    it "finds the spec by an alias (String)" do
      expect(described_class.specs_for_alias(namespace: :slash, token: "show")).to eq(spec_a)
    end

    it "returns nil for an unknown token" do
      expect(described_class.specs_for_alias(namespace: :slash, token: :unknown)).to be_nil
    end

    it "returns nil for a different namespace" do
      expect(described_class.specs_for_alias(namespace: :chat, token: :list)).to be_nil
    end
  end

  describe ".specs" do
    before do
      described_class.register_spec(spec_a)
      described_class.register_spec(spec_b)
      described_class.register_spec(chat_spec)
    end

    it "returns all specs for the given namespace" do
      result = described_class.specs(namespace: :slash)
      expect(result).to match_array([ spec_a, spec_b ])
    end

    it "returns only specs for the requested namespace" do
      result = described_class.specs(namespace: :chat)
      expect(result).to eq([ chat_spec ])
    end

    it "returns an empty array for an unregistered namespace" do
      expect(described_class.specs(namespace: :hashtag)).to eq([])
    end
  end

  describe ".register_vocabulary / .vocabulary" do
    it "retrieves a vocabulary by Symbol name" do
      described_class.register_vocabulary(vocab_genres)
      expect(described_class.vocabulary(:genres)).to eq(vocab_genres)
    end

    it "retrieves a vocabulary by String name" do
      described_class.register_vocabulary(vocab_genres)
      expect(described_class.vocabulary("genres")).to eq(vocab_genres)
    end

    it "returns nil for an unregistered vocabulary" do
      expect(described_class.vocabulary(:nonexistent)).to be_nil
    end
  end

  describe ".vocabularies" do
    it "returns all registered vocabularies" do
      described_class.register_vocabulary(vocab_genres)
      described_class.register_vocabulary(vocab_platforms)
      expect(described_class.vocabularies).to match_array([ vocab_genres, vocab_platforms ])
    end

    it "returns an empty array when nothing is registered" do
      expect(described_class.vocabularies).to eq([])
    end
  end

  describe ".reset!" do
    it "clears all registered specs" do
      described_class.register_spec(spec_a)
      described_class.reset!
      expect(described_class.specs(namespace: :slash)).to eq([])
    end

    it "clears alias index" do
      described_class.register_spec(spec_a)
      described_class.reset!
      expect(described_class.specs_for_alias(namespace: :slash, token: :ls)).to be_nil
    end

    it "clears all registered vocabularies" do
      described_class.register_vocabulary(vocab_genres)
      described_class.reset!
      expect(described_class.vocabularies).to eq([])
    end
  end

  describe ".register_all!" do
    it "runs without error when optional module constants are absent" do
      expect { described_class.register_all! }.not_to raise_error
    end

    it "clears any prior manual registrations before re-registering" do
      described_class.register_spec(spec_a)
      described_class.register_vocabulary(vocab_genres)

      described_class.register_all!

      # Manually registered spec_a should be gone (not re-registered by register_all!).
      expect(described_class.specs(namespace: :slash)).not_to include(spec_a)
      # The manually registered vocab_genres (name :genres) is replaced by the
      # canonical one from Pito::Grammar::Vocabularies, so it should NOT be nil —
      # but it should be the Vocabularies version, not the locally-defined stub.
      canonical_genres = Pito::Grammar::Vocabularies.all.find { |v| v.name == :genres }
      expect(described_class.vocabulary(:genres)).to eq(canonical_genres)
    end

    it "registers vocabularies from Pito::Grammar::Vocabularies" do
      described_class.register_all!
      # Pito::Grammar::Vocabularies is defined, so vocabularies should be non-empty
      # and include the :genres vocab.
      expect(described_class.vocabularies).not_to be_empty
      expect(described_class.vocabulary(:genres)).not_to be_nil
    end
  end
end
