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

    # Xbox bucket (Item 24 — no longer dropped)
    it "maps 'Xbox Series X|S' to ['xbox']" do
      expect(described_class.tokens([ "Xbox Series X|S" ])).to eq([ "xbox" ])
    end

    it "maps 'Xbox One' to ['xbox']" do
      expect(described_class.tokens([ "Xbox One" ])).to eq([ "xbox" ])
    end

    it "maps 'Xbox 360' to ['xbox']" do
      expect(described_class.tokens([ "Xbox 360" ])).to eq([ "xbox" ])
    end

    # Dropped platforms
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

    # ORDER — always PS → Switch → Xbox → Steam regardless of input order
    it "returns tokens in PS → Switch → Xbox → Steam order regardless of input order" do
      result = described_class.tokens([ "Steam", "Xbox One", "Nintendo Switch", "PlayStation 5" ])
      expect(result).to eq(%w[ps switch xbox steam])
    end

    it "returns PS before Steam when input lists Steam first" do
      result = described_class.tokens([ "Steam", "PlayStation 4" ])
      expect(result).to eq(%w[ps steam])
    end

    it "returns Switch before Steam when input lists Steam first" do
      result = described_class.tokens([ "GOG", "Nintendo Switch" ])
      expect(result).to eq(%w[switch steam])
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

    it "labels Xbox platforms as 'Xbox' (Item 24)" do
      expect(described_class.labels([ "Xbox Series X|S", "Xbox One" ])).to eq("Xbox")
    end

    it "returns nil for platforms that all drop (e.g. Stadia-only)" do
      expect(described_class.labels([ "Google Stadia" ])).to be_nil
    end
  end

  # ── icons_html ───────────────────────────────────────────────────────────────

  describe ".icons_html" do
    let(:all_platforms) { [ "Steam", "Nintendo Switch", "PlayStation 5" ] }

    subject(:html) { described_class.icons_html(all_platforms) }

    it "returns an html_safe string" do
      expect(html).to be_html_safe
    end

    it "wraps icons in a span.pito-platform-icons" do
      expect(html).to include('class="pito-platform-icons"')
    end

    it "contains three img tags" do
      expect(html.scan("<img").size).to eq(3)
    end

    it "includes the playstation SVG src" do
      expect(html).to include('src="/platforms/playstation.svg"')
    end

    it "includes the switch SVG src" do
      expect(html).to include('src="/platforms/switch.svg"')
    end

    it "includes the steam SVG src" do
      expect(html).to include('src="/platforms/steam.svg"')
    end

    it "uses pito-platform-icon class on each img" do
      expect(html.scan('class="pito-platform-icon"').size).to eq(3)
    end

    it "sets alt to the label text" do
      expect(html).to include('alt="PlayStation"')
      expect(html).to include('alt="Switch"')
      expect(html).to include('alt="Steam"')
    end

    it "emits icons in PS → Switch → Steam order regardless of input order" do
      ps_pos     = html.index("/platforms/playstation.svg")
      switch_pos = html.index("/platforms/switch.svg")
      steam_pos  = html.index("/platforms/steam.svg")
      expect(ps_pos).to be < switch_pos
      expect(switch_pos).to be < steam_pos
    end

    it "returns blank html_safe string for empty platforms" do
      result = described_class.icons_html([])
      expect(result).to be_blank
      expect(result).to be_html_safe
    end

    it "renders the Xbox icon for Xbox platforms (Item 24)" do
      result = described_class.icons_html([ "Xbox Series X|S" ])
      expect(result).to include('src="/platforms/xbox.svg"')
      expect(result).to include('alt="Xbox"')
    end

    it "emits Xbox between Switch and Steam in ORDER" do
      html = described_class.icons_html([ "Steam", "Xbox One", "Nintendo Switch", "PlayStation 5" ])
      positions = %w[playstation switch xbox steam].map { |p| html.index("/platforms/#{p}.svg") }
      expect(positions).to eq(positions.sort)
    end
  end
end
