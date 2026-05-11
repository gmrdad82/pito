require "rails_helper"

# Phase 27 §01b — Filter row helper.
RSpec.describe Games::FiltersHelper, type: :helper do
  describe "#parse_filter_tokens" do
    it "splits a CSV string into canonical tokens" do
      expect(helper.parse_filter_tokens("ps5,owned")).to eq(%w[ps5 owned])
    end

    it "returns [] for an empty string" do
      expect(helper.parse_filter_tokens("")).to eq([])
    end

    it "returns [] for nil" do
      expect(helper.parse_filter_tokens(nil)).to eq([])
    end

    it "accepts an Array input verbatim" do
      expect(helper.parse_filter_tokens(%w[ps5 owned])).to eq(%w[ps5 owned])
    end

    it "strips whitespace around tokens" do
      expect(helper.parse_filter_tokens("ps5, owned")).to eq(%w[ps5 owned])
    end

    it "drops unknown tokens" do
      expect(helper.parse_filter_tokens("ps5,bogus")).to eq([ "ps5" ])
    end

    it "de-duplicates tokens" do
      expect(helper.parse_filter_tokens("ps5,ps5,owned")).to eq(%w[ps5 owned])
    end

    it "normalises case" do
      expect(helper.parse_filter_tokens("PS5")).to eq([ "ps5" ])
    end

    it "ignores empty segments" do
      expect(helper.parse_filter_tokens(",ps5,,owned,")).to eq(%w[ps5 owned])
    end

    it "accepts every canonical token" do
      every = Games::Filter::CANONICAL_TOKENS.join(",")
      expect(helper.parse_filter_tokens(every)).to eq(Games::Filter::CANONICAL_TOKENS)
    end
  end

  describe "#parse_dropped_tokens" do
    it "returns the unrecognised tokens" do
      expect(helper.parse_dropped_tokens("ps5,bogus,owned")).to eq([ "bogus" ])
    end

    it "returns [] when all tokens are canonical" do
      expect(helper.parse_dropped_tokens("ps5,owned")).to eq([])
    end

    it "returns [] for nil" do
      expect(helper.parse_dropped_tokens(nil)).to eq([])
    end

    it "strips whitespace before classifying" do
      expect(helper.parse_dropped_tokens("ps5, bogus")).to eq([ "bogus" ])
    end
  end

  describe "#toggle_filter" do
    it "removes a token that is currently active" do
      expect(helper.toggle_filter([ "ps5" ], "ps5")).to eq([])
    end

    it "appends a token that is not currently active" do
      expect(helper.toggle_filter([ "ps5" ], "owned")).to eq(%w[ps5 owned])
    end

    it "does not mutate the input array" do
      input = [ "ps5" ]
      helper.toggle_filter(input, "owned")
      expect(input).to eq([ "ps5" ])
    end

    it "accepts a nil active list as []" do
      expect(helper.toggle_filter(nil, "ps5")).to eq([ "ps5" ])
    end
  end

  describe "#chip_label" do
    it "converts not_owned to a space-separated label" do
      expect(helper.chip_label("not_owned")).to eq("not owned")
    end

    # 2026-05-11 polish v2 — platform tokens render in canonical
    # marketing case (PS5, Switch2, Steam, GoG, Epic, Xbox); URL
    # tokens stay lowercase.
    {
      "ps5"     => "PS5",
      "switch2" => "Switch2",
      "steam"   => "Steam",
      "gog"     => "GoG",
      "epic"    => "Epic",
      "xbox"    => "Xbox"
    }.each do |token, expected_label|
      it "renders the platform token #{token.inspect} as #{expected_label.inspect}" do
        expect(helper.chip_label(token)).to eq(expected_label)
      end
    end

    it "passes through status / ownership tokens verbatim" do
      %w[recorded released scheduled owned].each do |t|
        expect(helper.chip_label(t)).to eq(t)
      end
    end
  end
end
