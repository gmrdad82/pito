# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::CommandHelp do
  describe ".call" do
    context "when verb is :list" do
      it "delegates to Game::ListHelp and returns its payload" do
        list_payload = Pito::MessageBuilder::Game::ListHelp.call
        result = described_class.call(verb: :list)

        expect(result).to be_a(Hash)
        expect(result["html"]).to be(true)
        expect(result["body"]).to eq(list_payload["body"])
      end
    end

    context "when verb is :show (has copy)" do
      it "returns an html payload" do
        result = described_class.call(verb: :show)
        expect(result).to be_a(Hash)
        expect(result["html"]).to be(true)
      end

      it "body includes a Usage: header" do
        body = described_class.call(verb: :show)["body"]
        expect(body).to include("Usage:")
      end

      it "body includes the show usage line (html-escaped)" do
        body = described_class.call(verb: :show)["body"]
        # <title> is html-escaped to &lt;title&gt;
        expect(body).to include("show")
        expect(body).to include("&lt;title&gt;")
      end

      it "body includes --help" do
        body = described_class.call(verb: :show)["body"]
        expect(body).to include("--help")
      end

      it "body is wrapped in .pito-help-block" do
        body = described_class.call(verb: :show)["body"]
        expect(body).to include('class="pito-help-block"')
      end
    end

    context "when verb is unknown (no copy)" do
      it "returns nil" do
        result = described_class.call(verb: :nope)
        expect(result).to be_nil
      end
    end
  end
end
