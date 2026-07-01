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
  end
end
