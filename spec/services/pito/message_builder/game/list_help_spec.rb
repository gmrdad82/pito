# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ListHelp do
  describe ".call" do
    subject(:result) { described_class.call }

    it "returns an html payload" do
      expect(result).to be_a(Hash)
      expect(result["html"]).to be(true)
      expect(result["body"]).to be_a(String)
    end

    it "body is wrapped in .pito-help-block" do
      expect(result["body"]).to include('class="pito-help-block"')
    end

    it "body includes 'Usage:'" do
      expect(result["body"]).to include("Usage:")
    end

    it "body includes the list games usage line" do
      expect(result["body"]).to include("list games")
    end

    it "body includes Options section" do
      expect(result["body"]).to include("Options:")
    end

    it "body includes Columns section" do
      expect(result["body"]).to include("Columns:")
    end

    it "body includes the platform column token" do
      expect(result["body"]).to include("platform")
    end

    it "body includes the genre column token" do
      expect(result["body"]).to include("genre")
    end

    it "body includes the developer column token" do
      expect(result["body"]).to include("developer")
    end

    it "body includes the publisher column token" do
      expect(result["body"]).to include("publisher")
    end

    it "body includes the channels column token" do
      expect(result["body"]).to include("channel")
    end

    it "no longer lists the removed release date / year columns (item 24)" do
      expect(result["body"]).not_to include("release date")
      expect(result["body"]).not_to match(/\byear\b/i)
    end

    it "body includes the footage column token" do
      expect(result["body"]).to include("footage")
    end

    it "body includes the with option" do
      expect(result["body"]).to include("with &lt;columns&gt;")
    end

    it "body includes the sort by option" do
      expect(result["body"]).to include("sort by &lt;column&gt;")
    end

    it "body includes --help option" do
      expect(result["body"]).to include("--help")
    end

    it "body includes channel column description" do
      expect(result["body"]).to include("@handles of channels with linked vids")
    end

    # G26.2 — views/likes audience-counter columns added to game list.
    it "body includes the views column token (G26.2)" do
      expect(result["body"]).to include("views")
    end

    it "body includes the likes column token (G26.2)" do
      expect(result["body"]).to include("likes")
    end

    it "body includes views column description — summed across linked vids (G26.2)" do
      expect(result["body"]).to include("summed across linked vids")
    end

    # U4 — filters are a first-class --help section, derived from the config.
    it "body includes a Filters section with the config game filters" do
      expect(result["body"]).to include("Filters:")
      expect(result["body"]).to include("upcoming")
      expect(result["body"]).to include("genre")
      expect(result["body"]).to include("platform")
    end

    it "renders a config filter description (single grammar)" do
      expect(result["body"]).to include("future or undated release")
    end

    # Regression: a vocabulary-backed filter (genre/platform — declares
    # `vocabulary:` but no literal `tokens:`) used to render a BLANK token
    # cell because `filter.tokens` was empty. These assertions are scoped to
    # the Filters-section slice of the body — "genre" and "platform" also
    # appear as Columns tokens, so an unscoped `include` (as above) cannot
    # actually catch a blank Filters row.
    describe "Filters section token cells" do
      subject(:filters_section) { result["body"][/Filters:.*/m] }

      it "renders a non-blank token for the token-backed upcoming filter" do
        expect(filters_section).to include('<span class="text-cyan">upcoming</span>')
      end

      it "renders a non-blank token for the vocabulary-backed genre filter (name fallback)" do
        expect(filters_section).to include('<span class="text-cyan">genre</span>')
      end

      it "renders a non-blank token for the vocabulary-backed platform filter (name fallback)" do
        expect(filters_section).to include('<span class="text-cyan">platform</span>')
      end

      it "never renders a blank token cell for any filter row" do
        expect(filters_section).not_to include('<span class="text-cyan"></span>')
      end
    end
  end
end
