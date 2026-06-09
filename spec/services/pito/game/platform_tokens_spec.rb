# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::PlatformTokens do
  # ── tokens ──────────────────────────────────────────────────────────────────

  describe ".tokens" do
    # PlayStation bucket
    it "maps 'PlayStation 5' to ['ps']" do
      expect(described_class.tokens([ "PlayStation 5" ])).to eq([ "ps" ])
    end

    it "maps 'PS4' to ['ps']" do
      expect(described_class.tokens([ "PS4" ])).to eq([ "ps" ])
    end

    it "maps 'PlayStation 3' to ['ps']" do
      expect(described_class.tokens([ "PlayStation 3" ])).to eq([ "ps" ])
    end

    # Switch bucket
    it "maps 'Nintendo Switch 2' to ['switch']" do
      expect(described_class.tokens([ "Nintendo Switch 2" ])).to eq([ "switch" ])
    end

    it "maps 'Switch Gen 1' to ['switch']" do
      expect(described_class.tokens([ "Switch Gen 1" ])).to eq([ "switch" ])
    end

    # Steam bucket
    it "maps 'Steam' to ['steam']" do
      expect(described_class.tokens([ "Steam" ])).to eq([ "steam" ])
    end

    it "maps 'PC (Microsoft Windows)' to ['steam']" do
      expect(described_class.tokens([ "PC (Microsoft Windows)" ])).to eq([ "steam" ])
    end

    it "maps 'GOG' to ['steam']" do
      expect(described_class.tokens([ "GOG" ])).to eq([ "steam" ])
    end

    it "maps 'Epic Games' to ['steam']" do
      expect(described_class.tokens([ "Epic Games" ])).to eq([ "steam" ])
    end

    it "maps 'Amazon' to ['steam']" do
      expect(described_class.tokens([ "Amazon" ])).to eq([ "steam" ])
    end

    it "maps 'Battle.net' to ['steam']" do
      expect(described_class.tokens([ "Battle.net" ])).to eq([ "steam" ])
    end

    # Dropped platforms
    it "drops 'Xbox Series X|S'" do
      expect(described_class.tokens([ "Xbox Series X|S" ])).to eq([])
    end

    it "drops 'Xbox One'" do
      expect(described_class.tokens([ "Xbox One" ])).to eq([])
    end

    it "drops 'Google Stadia'" do
      expect(described_class.tokens([ "Google Stadia" ])).to eq([])
    end

    it "drops 'Mac'" do
      expect(described_class.tokens([ "Mac" ])).to eq([])
    end

    # De-duplication
    it "de-dupes tokens when multiple IGDB names map to the same bucket" do
      expect(described_class.tokens([ "PlayStation 4", "PlayStation 5" ])).to eq([ "ps" ])
    end
  end

  # ── labels ──────────────────────────────────────────────────────────────────

  describe ".labels" do
    it "returns comma-joined display names for known platforms" do
      result = described_class.labels([ "PlayStation 5", "Nintendo Switch 2", "Steam" ])
      expect(result).to eq("PlayStation, Switch, Steam")
    end

    it "returns nil for an empty array" do
      expect(described_class.labels([])).to be_nil
    end

    it "returns nil for platforms that all drop (e.g. Xbox-only)" do
      expect(described_class.labels([ "Xbox Series X|S", "Xbox One" ])).to be_nil
    end
  end
end
