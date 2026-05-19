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
        ps switch steam
      ])
    end

    it "is frozen" do
      expect(universe).to be_frozen
    end
  end

  describe "#parse_checked_tokens" do
    it "returns DEFAULT_CHECKED_TOKENS for nil (param ABSENT means default-checked set — universe MINUS played, user-locked 2026-05-17)" do
      expect(helper.parse_checked_tokens(nil))
        .to eq(Games::FiltersHelper::DEFAULT_CHECKED_TOKENS)
    end

    it "returns an empty array for an empty string (every chip off — edge state)" do
      expect(helper.parse_checked_tokens("")).to eq([])
    end

    it "parses a CSV into the checked-token set" do
      expect(helper.parse_checked_tokens("ps,owned")).to match_array(%w[ps owned])
    end

    it "preserves TOKEN_UNIVERSE order regardless of input order" do
      expect(helper.parse_checked_tokens("steam,ps,owned,released"))
        .to eq(%w[released owned ps steam])
    end

    it "accepts an Array input verbatim" do
      expect(helper.parse_checked_tokens(%w[ps owned])).to match_array(%w[ps owned])
    end

    it "strips whitespace around tokens" do
      expect(helper.parse_checked_tokens("ps, owned")).to match_array(%w[ps owned])
    end

    it "drops unknown tokens silently" do
      expect(helper.parse_checked_tokens("ps,bogus,owned")).to match_array(%w[ps owned])
    end

    it "drops the legacy xbox token (no chip in v2)" do
      expect(helper.parse_checked_tokens("ps,xbox")).to eq([ "ps" ])
    end

    it "drops the legacy gog token (collapsed into steam 2026-05-17)" do
      expect(helper.parse_checked_tokens("ps,gog")).to eq([ "ps" ])
    end

    it "drops the legacy epic token (collapsed into steam 2026-05-17)" do
      expect(helper.parse_checked_tokens("ps,epic")).to eq([ "ps" ])
    end

    it "drops the legacy not_owned token (no chip in v2)" do
      expect(helper.parse_checked_tokens("not_owned,owned")).to eq([ "owned" ])
    end

    it "drops the legacy recorded token (no chip in v2)" do
      expect(helper.parse_checked_tokens("recorded,played")).to eq([ "played" ])
    end

    it "de-duplicates tokens" do
      expect(helper.parse_checked_tokens("ps,ps,owned")).to match_array(%w[ps owned])
    end

    it "normalises case" do
      expect(helper.parse_checked_tokens("PS")).to eq([ "ps" ])
    end

    it "ignores empty segments" do
      expect(helper.parse_checked_tokens(",ps,,owned,")).to match_array(%w[ps owned])
    end
  end

  describe "#serialize_checked_tokens" do
    it "returns the empty string when the input is empty" do
      expect(helper.serialize_checked_tokens([])).to eq("")
    end

    it "returns a CSV in TOKEN_UNIVERSE order regardless of input order" do
      expect(helper.serialize_checked_tokens(%w[steam ps owned])).to eq("owned,ps,steam")
    end

    it "drops unknown tokens silently" do
      expect(helper.serialize_checked_tokens(%w[ps bogus])).to eq("ps")
    end

    it "returns every token CSV when given the universe" do
      expect(helper.serialize_checked_tokens(universe)).to eq(universe.join(","))
    end
  end

  describe "#games_path_with_checked" do
    it "emits /games when DEFAULT_CHECKED_TOKENS is the set (universe MINUS played — the canonical full-list URL, user-locked 2026-05-17)" do
      expect(helper.games_path_with_checked(Games::FiltersHelper::DEFAULT_CHECKED_TOKENS))
        .to eq("/games")
    end

    it "emits /games?filters=<csv> for the explicit-universe (played included is a meaningful, user-visible state)" do
      # Adding `played` is NOT canonicalised to bare `/games` — the
      # canonical full-list URL is universe MINUS played.
      expect(helper.games_path_with_checked(universe))
        .to eq("/games?filters=#{universe.join(',')}")
    end

    it "emits /games?filters=<csv> for a subset" do
      expect(helper.games_path_with_checked([ "ps" ])).to eq("/games?filters=ps")
    end

    it "emits /games?filters= (empty CSV) when the set is empty" do
      expect(helper.games_path_with_checked([])).to eq("/games?filters=")
    end

    it "honors a custom request_path" do
      expect(helper.games_path_with_checked([ "ps" ], path: "/games"))
        .to eq("/games?filters=ps")
    end

    it "drops unknown tokens before deciding whether to emit /games" do
      # DEFAULT_CHECKED_TOKENS + 1 unknown still equals "default-checked
      # set" → /games. The unknown token never reaches the comparison.
      result = helper.games_path_with_checked(
        Games::FiltersHelper::DEFAULT_CHECKED_TOKENS + [ "bogus" ]
      )
      expect(result).to eq("/games")
    end
  end

  describe "#chip_label" do
    # Platform tokens render in canonical short form (PS, Switch,
    # Steam). Status / ownership tokens render verbatim. GoG + Epic
    # were collapsed into Steam in the 2026-05-17 PC store collapse.
    {
      "ps"     => "PS",
      "switch" => "Switch",
      "steam"  => "Steam"
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
