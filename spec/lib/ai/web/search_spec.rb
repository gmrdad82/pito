# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Web::Search, type: :service do
  let(:endpoint) { "https://api.tavily.com/search" }

  describe ".configured?" do
    it "is false without a tavily_api_key and true with one" do
      expect(described_class.configured?).to be(false)
      AppSetting.set("tavily_api_key", "tvly-test")
      expect(described_class.configured?).to be(true)
    end
  end

  describe ".call" do
    context "when configured" do
      before { AppSetting.set("tavily_api_key", "tvly-test") }

      it "POSTs the JSON body and maps Tavily results (content → snippet), capped at 5" do
        stub = stub_request(:post, endpoint)
               .with(
                 headers: { "Content-Type" => "application/json" },
                 body:    { api_key: "tvly-test", query: "subnautica 2 release", max_results: 5 }.to_json
               )
               .to_return(
                 status:  200,
                 body:    { results: (1..7).map do |n|
                   { title: "Result #{n}", url: "https://example.com/#{n}", content: "Snippet #{n}" }
                 end }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )

        result = described_class.call(query: "subnautica 2 release")

        expect(stub).to have_been_requested
        expect(result[:results].length).to eq(5)
        expect(result[:results].first).to eq(
          title:   "Result 1",
          url:     "https://example.com/1",
          snippet: "Snippet 1"
        )
      end

      it "returns an HTTP error hash on a non-2xx response" do
        stub_request(:post, endpoint).to_return(status: 429, body: "", headers: {})

        expect(described_class.call(query: "anything")).to eq(error: "search failed (HTTP 429)")
      end

      it "never raises on a network error — it logs a warning and returns { error: }" do
        stub_request(:post, endpoint).to_timeout

        expect(Rails.logger).to receive(:warn).with(/Ai::Web::Search/)
        result = described_class.call(query: "anything")
        expect(result).to match(error: /search failed/)
      end

      it "never raises on a malformed JSON body — it logs a warning and returns { error: }" do
        stub_request(:post, endpoint).to_return(status: 200, body: "not json{", headers: {})

        expect(Rails.logger).to receive(:warn).with(/Ai::Web::Search/)
        expect(described_class.call(query: "anything")).to match(error: /search failed/)
      end
    end

    it "returns the /config hint without a request when unconfigured" do
      result = described_class.call(query: "anything")

      expect(result).to eq(error: "web search isn't configured (/config tavily api_key=…)")
      expect(WebMock).not_to have_requested(:post, endpoint)
    end

    it "rejects a blank query without a request" do
      AppSetting.set("tavily_api_key", "tvly-test")

      expect(described_class.call(query: "   ")).to eq(error: "empty query")
      expect(WebMock).not_to have_requested(:post, endpoint)
    end
  end
end
