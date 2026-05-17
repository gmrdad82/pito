require "rails_helper"

# Phase 27 v2 spec 06 — Filter row helper.
#
# v2 contract: `?filters=<csv>` is the SET OF CHECKED chips. Empty
# param ABSENT means "every chip checked" (full list URL). Empty CSV
# means "every chip off" (empty listing edge state).
RSpec.describe Games::FiltersHelper, type: :helper do
  let(:universe) { Games::FiltersHelper::TOKEN_UNIVERSE }

  describe "TOKEN_UNIVERSE constant" do
    # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `gog` and
    # `epic` chips were retired; the three PC stores converge on
    # `steam`. The universe now has eight canonical tokens.
    it "lists the eight v2 canonical tokens in render order" do
      expect(universe).to eq(%w[
        released scheduled owned wishlist played
        ps5 switch2 steam
      ])
    end

    it "is frozen" do
      expect(universe).to be_frozen
    end
  end

  describe "#parse_checked_tokens" do
    it "returns the FULL universe for nil (param ABSENT means every chip checked)" do
      expect(helper.parse_checked_tokens(nil)).to eq(universe)
    end

    it "returns an empty array for an empty string (every chip off — edge state)" do
      expect(helper.parse_checked_tokens("")).to eq([])
    end

    it "parses a CSV into the checked-token set" do
      expect(helper.parse_checked_tokens("ps5,owned")).to match_array(%w[ps5 owned])
    end

    it "preserves TOKEN_UNIVERSE order regardless of input order" do
      expect(helper.parse_checked_tokens("steam,ps5,owned,released"))
        .to eq(%w[released owned ps5 steam])
    end

    it "accepts an Array input verbatim" do
      expect(helper.parse_checked_tokens(%w[ps5 owned])).to match_array(%w[ps5 owned])
    end

    it "strips whitespace around tokens" do
      expect(helper.parse_checked_tokens("ps5, owned")).to match_array(%w[ps5 owned])
    end

    it "drops unknown tokens silently" do
      expect(helper.parse_checked_tokens("ps5,bogus,owned")).to match_array(%w[ps5 owned])
    end

    it "drops the legacy xbox token (no chip in v2)" do
      expect(helper.parse_checked_tokens("ps5,xbox")).to eq([ "ps5" ])
    end

    it "drops the legacy gog token (collapsed into steam 2026-05-17)" do
      expect(helper.parse_checked_tokens("ps5,gog")).to eq([ "ps5" ])
    end

    it "drops the legacy epic token (collapsed into steam 2026-05-17)" do
      expect(helper.parse_checked_tokens("ps5,epic")).to eq([ "ps5" ])
    end

    it "drops the legacy not_owned token (no chip in v2)" do
      expect(helper.parse_checked_tokens("not_owned,owned")).to eq([ "owned" ])
    end

    it "drops the legacy recorded token (no chip in v2)" do
      expect(helper.parse_checked_tokens("recorded,played")).to eq([ "played" ])
    end

    it "de-duplicates tokens" do
      expect(helper.parse_checked_tokens("ps5,ps5,owned")).to match_array(%w[ps5 owned])
    end

    it "normalises case" do
      expect(helper.parse_checked_tokens("PS5")).to eq([ "ps5" ])
    end

    it "ignores empty segments" do
      expect(helper.parse_checked_tokens(",ps5,,owned,")).to match_array(%w[ps5 owned])
    end
  end

  describe "#serialize_checked_tokens" do
    it "returns the empty string when the input is empty" do
      expect(helper.serialize_checked_tokens([])).to eq("")
    end

    it "returns a CSV in TOKEN_UNIVERSE order regardless of input order" do
      expect(helper.serialize_checked_tokens(%w[steam ps5 owned])).to eq("owned,ps5,steam")
    end

    it "drops unknown tokens silently" do
      expect(helper.serialize_checked_tokens(%w[ps5 bogus])).to eq("ps5")
    end

    it "returns every token CSV when given the universe" do
      expect(helper.serialize_checked_tokens(universe)).to eq(universe.join(","))
    end
  end

  describe "#games_path_with_checked" do
    it "emits /games when every chip is checked (the canonical full-list URL)" do
      expect(helper.games_path_with_checked(universe)).to eq("/games")
    end

    it "emits /games?filters=<csv> for a subset" do
      expect(helper.games_path_with_checked([ "ps5" ])).to eq("/games?filters=ps5")
    end

    it "emits /games?filters= (empty CSV) when the set is empty" do
      expect(helper.games_path_with_checked([])).to eq("/games?filters=")
    end

    it "honors a custom request_path" do
      expect(helper.games_path_with_checked([ "ps5" ], path: "/games"))
        .to eq("/games?filters=ps5")
    end

    it "drops unknown tokens before deciding whether to emit /games" do
      # Universe + 1 unknown still equals "universe checked" → /games.
      result = helper.games_path_with_checked(universe + [ "bogus" ])
      expect(result).to eq("/games")
    end
  end

  describe "#chip_label" do
    # Platform tokens render in canonical short form (PS5, Switch2,
    # Steam). Status / ownership tokens render verbatim. GoG + Epic
    # were collapsed into Steam in the 2026-05-17 PC store collapse.
    {
      "ps5"     => "PS5",
      "switch2" => "Switch2",
      "steam"   => "Steam"
    }.each do |token, expected_label|
      it "renders #{token.inspect} as #{expected_label.inspect}" do
        expect(helper.chip_label(token)).to eq(expected_label)
      end
    end

    it "passes status / ownership tokens through verbatim" do
      %w[released scheduled owned wishlist played].each do |t|
        expect(helper.chip_label(t)).to eq(t)
      end
    end
  end
end
