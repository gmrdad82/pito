# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::Vocabulary do
  let(:static_vocab) do
    described_class.define(
      name: :genres,
      canonical: [ "Shooter", "Simulation", "RPG" ],
      synonyms: { "fps" => "Shooter", "sim" => "Simulation" },
      fillers: [ "count", "ratio" ],
      dynamic: false,
      resolver: nil
    )
  end

  let(:dynamic_resolver) { ->(context) { [ "@channel_a", "@channel_b" ] } }

  let(:dynamic_vocab) do
    described_class.define(
      name: :channels,
      canonical: [],
      synonyms: {},
      fillers: [],
      dynamic: true,
      resolver: dynamic_resolver
    )
  end

  describe ".define" do
    it "builds a Vocabulary instance" do
      expect(static_vocab).to be_a(described_class)
    end

    it "sets name as a Symbol" do
      expect(static_vocab.name).to eq(:genres)
    end

    it "dynamic? reflects the dynamic flag (false)" do
      expect(static_vocab.dynamic?).to be false
    end

    it "dynamic? reflects the dynamic flag (true)" do
      expect(dynamic_vocab.dynamic?).to be true
    end
  end

  describe "#resolve" do
    it "finds a canonical member with exact casing" do
      expect(static_vocab.resolve("RPG")).to eq("RPG")
    end

    it "finds a canonical member case-insensitively (lowercase input)" do
      expect(static_vocab.resolve("rpg")).to eq("RPG")
    end

    it "finds a canonical member case-insensitively (mixed casing)" do
      expect(static_vocab.resolve("Shooter")).to eq("Shooter")
    end

    it "maps a synonym to its canonical value" do
      expect(static_vocab.resolve("fps")).to eq("Shooter")
    end

    it "maps a synonym case-insensitively (uppercase synonym)" do
      expect(static_vocab.resolve("FPS")).to eq("Shooter")
    end

    it "returns nil for an unknown token" do
      expect(static_vocab.resolve("MOBA")).to be_nil
    end

    it "returns nil for nil input" do
      expect(static_vocab.resolve(nil)).to be_nil
    end

    it "returns nil for empty string input" do
      expect(static_vocab.resolve("")).to be_nil
    end

    it "returns nil for whitespace-only input" do
      expect(static_vocab.resolve("   ")).to be_nil
    end

    context "with a dynamic vocab" do
      it "calls the resolver and returns a case-insensitive match" do
        expect(dynamic_vocab.resolve("@channel_a")).to eq("@channel_a")
      end

      it "returns nil when the resolver has no match" do
        expect(dynamic_vocab.resolve("@unknown")).to be_nil
      end
    end
  end

  describe "#filler?" do
    it "returns true for a known filler word" do
      expect(static_vocab.filler?("count")).to be true
    end

    it "returns true for a filler word case-insensitively" do
      expect(static_vocab.filler?("COUNT")).to be true
    end

    it "returns false for a non-filler word" do
      expect(static_vocab.filler?("Shooter")).to be false
    end

    it "returns false for an empty string" do
      expect(static_vocab.filler?("")).to be false
    end
  end

  describe "#members" do
    it "returns canonical for a static vocab" do
      expect(static_vocab.members(context: nil)).to eq([ "Shooter", "Simulation", "RPG" ])
    end

    it "returns resolver output for a dynamic vocab (stub lambda, no DB)" do
      stub_context = Object.new
      result = dynamic_vocab.members(context: stub_context)
      expect(result).to eq([ "@channel_a", "@channel_b" ])
    end

    it "returns [] for a dynamic vocab with no resolver" do
      vocab = described_class.define(name: :empty, dynamic: true, resolver: nil)
      expect(vocab.members(context: nil)).to eq([])
    end
  end

  describe "#to_h" do
    context "static vocab" do
      subject(:hash) { static_vocab.to_h }

      it "includes name" do
        expect(hash[:name]).to eq(:genres)
      end

      it "includes canonical members" do
        expect(hash[:canonical]).to eq([ "Shooter", "Simulation", "RPG" ])
      end

      it "includes downcased synonym keys" do
        expect(hash[:synonyms]).to eq({ "fps" => "Shooter", "sim" => "Simulation" })
      end

      it "includes fillers as an array" do
        expect(hash[:fillers]).to match_array([ "count", "ratio" ])
      end

      it "includes dynamic: false" do
        expect(hash[:dynamic]).to be false
      end
    end

    context "dynamic vocab" do
      subject(:hash) { dynamic_vocab.to_h }

      it "includes name" do
        expect(hash[:name]).to eq(:channels)
      end

      it "does NOT include canonical members" do
        expect(hash).not_to have_key(:canonical)
      end

      it "does NOT include members key" do
        expect(hash.keys).not_to include(:members)
      end

      it "includes dynamic: true" do
        expect(hash[:dynamic]).to be true
      end

      it "includes synonyms" do
        expect(hash[:synonyms]).to eq({})
      end

      it "includes fillers as an array" do
        expect(hash[:fillers]).to eq([])
      end
    end
  end
end
