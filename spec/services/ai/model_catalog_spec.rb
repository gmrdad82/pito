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
end
