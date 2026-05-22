require "rails_helper"

RSpec.describe Pito::Transitions::Effects do
  describe "EFFECTS" do
    it "is frozen" do
      expect(described_class::EFFECTS).to be_frozen
    end

    it "has exactly 3 entries" do
      expect(described_class::EFFECTS.keys.size).to eq(3)
    end

    it "registers scramble_settle, color_crossfade, shimmer" do
      expect(described_class::EFFECTS.keys).to contain_exactly(
        :scramble_settle, :color_crossfade, :shimmer
      )
    end

    it "marks scramble_settle as a transition" do
      expect(described_class::EFFECTS[:scramble_settle][:kind]).to eq(:transition)
    end

    it "marks color_crossfade as a transition" do
      expect(described_class::EFFECTS[:color_crossfade][:kind]).to eq(:transition)
    end

    it "marks shimmer as a decoration" do
      expect(described_class::EFFECTS[:shimmer][:kind]).to eq(:decoration)
    end

    it "references valid Tokens for every effect" do
      described_class::EFFECTS.each_value do |effect|
        effect[:tokens].each do |token_key|
          expect(Pito::Transitions::Tokens::ALL).to have_key(token_key)
        end
      end
    end
  end

  describe ".transition_names" do
    it "returns the two transitions in registry order" do
      expect(described_class.transition_names).to eq([ :scramble_settle, :color_crossfade ])
    end
  end

  describe ".decoration_names" do
    it "returns the shimmer decoration" do
      expect(described_class.decoration_names).to eq([ :shimmer ])
    end
  end

  describe ".all_names" do
    it "returns all 3 effect keys" do
      expect(described_class.all_names).to eq([ :scramble_settle, :color_crossfade, :shimmer ])
    end
  end
end
