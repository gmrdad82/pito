# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::PlatformInput do
  describe ".normalize" do
    # The contract: every PlayStation spelling variant must converge to a string
    # that PlatformTokens maps back to the "ps" logo family.
    %w[PS5 ps5 PlayStation\ 5 PlayStation5 ps4 PS\ 4 ps playstation].each do |input|
      it "maps #{input.inspect} into the PlayStation logo family" do
        normalized = described_class.normalize(input)
        expect(Pito::Game::PlatformTokens.tokens([ normalized ])).to eq([ "ps" ])
      end
    end

    it "preserves the console number when present" do
      expect(described_class.normalize("ps5")).to eq("PlayStation 5")
      expect(described_class.normalize("PlayStation5")).to eq("PlayStation 5")
      expect(described_class.normalize("ps4")).to eq("PlayStation 4")
    end

    it "drops the number for a bare PlayStation reference" do
      expect(described_class.normalize("ps")).to eq("PlayStation")
    end

    %w[switch Switch nintendo\ switch].each do |input|
      it "maps #{input.inspect} to Nintendo Switch (switch logo)" do
        expect(described_class.normalize(input)).to eq("Nintendo Switch")
        expect(Pito::Game::PlatformTokens.tokens([ described_class.normalize(input) ])).to eq([ "switch" ])
      end
    end

    %w[steam pc PC windows gog epic].each do |input|
      it "maps #{input.inspect} to PC (Steam) (steam logo)" do
        expect(described_class.normalize(input)).to eq("PC (Steam)")
        expect(Pito::Game::PlatformTokens.tokens([ described_class.normalize(input) ])).to eq([ "steam" ])
      end
    end

    it "titleizes Xbox input and resolves it to the xbox token/logo (Item 24)" do
      expect(described_class.normalize("xbox")).to eq("Xbox")
      expect(described_class.normalize("xbox one")).to eq("Xbox One")
      expect(described_class.normalize("xbox series x")).to eq("Xbox Series X")
      %w[Xbox Xbox\ One Xbox\ Series\ X].each do |name|
        expect(Pito::Game::PlatformTokens.tokens([ name ])).to eq([ "xbox" ])
      end
    end

    it "stores unknown platforms as cleaned/titleized text with no logo" do
      expect(described_class.normalize("google stadia")).to eq("Google Stadia")
      expect(Pito::Game::PlatformTokens.tokens([ described_class.normalize("google stadia") ])).to be_empty
    end

    it "returns an empty string for blank input" do
      expect(described_class.normalize("  ")).to eq("")
      expect(described_class.normalize(nil)).to eq("")
    end
  end
end
