# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::PriceGlyphs do
  describe ".html" do
    # ── coins + number (the € is replaced by the coins) ─────────────────────
    it "renders N coin imgs matching the tier, then the bare number" do
      html = described_class.html(BigDecimal("59.99"))
      expect(html.scan(%r{<img[^>]*class="pito-coin"}).size).to eq(3)
      expect(html).to include("/coin/coin.gif")
      expect(html).to include("59.99")
      expect(html).not_to include("€")
    end

    it "draws 1 coin at the budget tier and 5 at premium" do
      expect(described_class.html(BigDecimal("4.99")).scan("pito-coin\"").size).to eq(1)
      expect(described_class.html(BigDecimal("99.99")).scan("pito-coin\"").size).to eq(5)
    end

    it "wraps the coins in a .pito-coins span" do
      expect(described_class.html(BigDecimal("19.99"))).to include('<span class="pito-coins">')
    end

    # ── explicit 0 → the star + "0.00" (glyph + number, like the coins) ─────
    it "renders the FREE star AND the 0.00 number for an explicit 0 / 0.0" do
      html = described_class.html(0)
      expect(html).to include("/coin/star.gif")
      expect(html).to include("pito-coin--free")
      expect(html).to include("0.00")
      expect(html).not_to include("/coin/coin.gif")
      expect(html).not_to include("€")
    end

    # ── nil → em-dash (unpriced), NOT a star ────────────────────────────────
    it "renders the em-dash for nil (unpriced) — no star, no coin" do
      html = described_class.html(nil)
      expect(html).to eq("—")
      expect(html).not_to include("/coin/star.gif")
      expect(html).not_to include("/coin/coin.gif")
    end

    # ── html-safety ─────────────────────────────────────────────────────────
    it "returns an html_safe String" do
      expect(described_class.html(BigDecimal("29.99"))).to be_html_safe
      expect(described_class.html(nil)).to be_html_safe
    end
  end
end
