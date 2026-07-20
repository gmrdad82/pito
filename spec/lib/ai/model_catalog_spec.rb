# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::ModelCatalog, type: :service do
  let(:models_url) { "https://opencode.ai/zen/v1/models" }
  let(:pinned_fallback) do
    Ai::ProviderRegistry.provider(:opencode)[:pinned_models].map { |id| { id: id, pinned: true } }
  end

  describe ".models" do
    context "live fetch happy path" do
      it "returns the OpenAI-shaped ids in source order as {id:, pinned: false}" do
        stub_request(:get, models_url).to_return(
          status:  200,
          body:    { object: "list", data: [
            { id: "model-a" }, { id: "model-b" }, { id: "model-c" }
          ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        expect(described_class.models(provider: :opencode)).to eq([
          { id: "model-a", pinned: false },
          { id: "model-b", pinned: false },
          { id: "model-c", pinned: false }
        ])
      end
    end

    context "row pricing (per-1M-token input/output, the computed-cost fallback's source)" do
      it "retains a row's pricing as {input:, output:} when the listing carries one" do
        stub_request(:get, models_url).to_return(
          status:  200,
          body:    { data: [
            { id: "model-a", pricing: { input: 3.0, output: 15.0 } },
            { id: "model-b" }
          ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        expect(described_class.models(provider: :opencode)).to eq([
          { id: "model-a", pinned: false, pricing: { input: 3.0, output: 15.0 } },
          { id: "model-b", pinned: false }
        ])
      end

      it "keeps the plain {id:, pinned:} shape when pricing is missing, malformed, or incomplete" do
        stub_request(:get, models_url).to_return(
          status:  200,
          body:    { data: [
            { id: "model-a" },
            { id: "model-b", pricing: "cheap" },
            { id: "model-c", pricing: { input: 3.0 } }
          ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        expect(described_class.models(provider: :opencode)).to eq([
          { id: "model-a", pinned: false },
          { id: "model-b", pinned: false },
          { id: "model-c", pinned: false }
        ])
      end
    end

    context "live: false (the picker's keyless-provider path)" do
      it "issues NO request and serves the pinned fallback when nothing is cached" do
        result = described_class.models(provider: :opencode, live: false)

        expect(result).to eq(pinned_fallback)
        expect(WebMock).not_to have_requested(:get, models_url)
      end

      it "serves an already-cached live list without a request" do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)
        cache.write(described_class.cache_key(:opencode), [ { id: "cached", pinned: false } ])

        result = described_class.models(provider: :opencode, live: false)

        expect(result).to eq([ { id: "cached", pinned: false } ])
        expect(WebMock).not_to have_requested(:get, models_url)
      end
    end

    context "auth header" do
      it "sends Authorization: Bearer <key> when an API key is configured" do
        AppSetting.set("opencode_api_key", "sk-test")
        stub = stub_request(:get, models_url)
               .with(headers: { "Authorization" => "Bearer sk-test" })
               .to_return(
                 status:  200,
                 body:    { data: [ { id: "model-a" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )

        described_class.models(provider: :opencode)

        expect(stub).to have_been_requested
      end

      it "sends no Authorization header when no API key is configured" do
        stub = stub_request(:get, models_url)
               .with { |request| !request.headers.to_h.key?("Authorization") }
               .to_return(
                 status:  200,
                 body:    { data: [ { id: "model-a" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" }
               )

        described_class.models(provider: :opencode)

        expect(stub).to have_been_requested
      end
    end

    it "skips rows with a blank or missing id" do
      stub_request(:get, models_url).to_return(
        status:  200,
        body:    { data: [
          { id: "model-a" }, { id: "" }, { id: nil }, {}, { id: "model-b" }
        ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect(described_class.models(provider: :opencode)).to eq([
        { id: "model-a", pinned: false },
        { id: "model-b", pinned: false }
      ])
    end

    it "falls back to pinned models and logs a warning on a non-2xx response" do
      stub_request(:get, models_url).to_return(status: 500, body: "", headers: {})

      expect(Rails.logger).to receive(:warn).with(/non-2xx response/)
      expect(described_class.models(provider: :opencode)).to eq(pinned_fallback)
    end

    it "falls back to pinned models on a timeout/network error" do
      stub_request(:get, models_url).to_timeout

      expect(Rails.logger).to receive(:warn)
      expect(described_class.models(provider: :opencode)).to eq(pinned_fallback)
    end

    it "falls back to pinned models on a malformed JSON body" do
      stub_request(:get, models_url).to_return(
        status:  200,
        body:    "not json{",
        headers: { "Content-Type" => "application/json" }
      )

      expect(Rails.logger).to receive(:warn)
      expect(described_class.models(provider: :opencode)).to eq(pinned_fallback)
    end

    context "caching (memory store)" do
      before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

      it "hits HTTP once, then serves the second call within TTL from cache" do
        stub = stub_request(:get, models_url).to_return(
          status:  200,
          body:    { data: [ { id: "model-a" } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

        described_class.models(provider: :opencode)
        described_class.models(provider: :opencode)

        expect(stub).to have_been_requested.times(1)
      end

      it "does not cache a failed call — the next call re-attempts HTTP" do
        stub = stub_request(:get, models_url).to_return(status: 500, body: "", headers: {})
        allow(Rails.logger).to receive(:warn)

        described_class.models(provider: :opencode)
        described_class.models(provider: :opencode)

        expect(stub).to have_been_requested.times(2)
      end
    end

    context "unknown provider" do
      it "raises KeyError" do
        expect { described_class.models(provider: :nope) }.to raise_error(KeyError)
      end
    end
  end

  describe ".bust!" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "clears the cached result so the next call re-fetches" do
      stub = stub_request(:get, models_url).to_return(
        status:  200,
        body:    { data: [ { id: "model-a" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      described_class.models(provider: :opencode)
      described_class.bust!(provider: :opencode)
      described_class.models(provider: :opencode)

      expect(stub).to have_been_requested.times(2)
    end
  end

  describe ".pricing_for" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "returns the cached row's per-1M pricing, issuing NO request (cache-only)" do
      Rails.cache.write(described_class.cache_key(:opencode), [
        { id: "model-a", pinned: false, pricing: { input: 3.0, output: 15.0 } }
      ])

      expect(described_class.pricing_for(provider: :opencode, model: "model-a"))
        .to eq({ input: 3.0, output: 15.0 })
      expect(WebMock).not_to have_requested(:get, models_url)
    end

    it "returns nil when the cached row carries no pricing and no pin exists" do
      Rails.cache.write(described_class.cache_key(:opencode), [ { id: "model-a", pinned: false } ])

      expect(described_class.pricing_for(provider: :opencode, model: "model-a")).to be_nil
    end

    it "returns nil for a model the cache/pinned fallback doesn't know" do
      expect(described_class.pricing_for(provider: :opencode, model: "nope")).to be_nil
    end

    context "config-pinned pricing fallback (ai_providers.yml pinned_pricing)" do
      it "prefers the cached catalog row's pricing over the config pin when both exist" do
        Rails.cache.write(described_class.cache_key(:opencode), [
          { id: "claude-sonnet-5", pinned: false, pricing: { input: 2.0, output: 10.0 } }
        ])

        expect(described_class.pricing_for(provider: :opencode, model: "claude-sonnet-5"))
          .to eq({ input: 2.0, output: 10.0 })
      end

      it "serves the pin when the cached row carries none (OpenCode Zen's pricing-less listing)" do
        Rails.cache.write(described_class.cache_key(:opencode), [
          { id: "claude-sonnet-5", pinned: false }
        ])

        expect(described_class.pricing_for(provider: :opencode, model: "claude-sonnet-5"))
          .to eq({ input: 3.0, output: 15.0 })
      end

      it "serves the pin on a cold cache too, still issuing NO request (the anthropic case)" do
        expect(described_class.pricing_for(provider: :anthropic, model: "claude-haiku-4-5"))
          .to eq({ input: 1.0, output: 5.0 })
        expect(WebMock).not_to have_requested(:get, /api\.anthropic\.com/)
      end

      it "returns nil for a model with neither catalog pricing nor a pin (unknown stays costless)" do
        Rails.cache.write(described_class.cache_key(:opencode), [ { id: "big-pickle", pinned: false } ])

        expect(described_class.pricing_for(provider: :opencode, model: "big-pickle")).to be_nil
      end
    end
  end
end
