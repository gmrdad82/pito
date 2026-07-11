# frozen_string_literal: true

require "rails_helper"

# Contract for Ai::ProviderRegistry — the cached loader + validator for
# config/pito/ai_providers.yml. The happy-path examples run against the REAL
# shipped YAML (no injection); the validation examples stub YAML.safe_load_file
# (the seam load! reads through) with a synthetic document and always
# reload! afterwards so later examples see the real config again.
RSpec.describe Ai::ProviderRegistry do
  after { described_class.reload! }

  describe ".provider_names" do
    it "lists every declared provider, opencode first, against the real config" do
      expect(described_class.provider_names).to eq(
        %i[opencode openrouter huggingface deepseek openai anthropic qwen glm gemini]
      )
    end
  end

  describe ".provider" do
    it "returns the frozen opencode descriptor" do
      descriptor = described_class.provider(:opencode)

      expect(descriptor[:base_url]).to eq("https://opencode.ai/zen/v1")
      expect(descriptor[:wire]).to eq("openai_chat")
      expect(descriptor[:auth]).to eq("bearer")
      expect(descriptor[:pinned_models]).not_to be_empty
      expect(descriptor).to be_frozen
    end

    it "accepts a String name" do
      expect(described_class.provider("opencode")[:label]).to eq("OpenCode Zen")
    end

    it "raises KeyError for an unknown provider" do
      expect { described_class.provider(:nope) }.to raise_error(KeyError, /unknown provider/)
    end
  end

  describe ".reload!" do
    it "clears memoization so a subsequent call reloads without error" do
      first = described_class.provider_names

      described_class.reload!
      second = described_class.provider_names

      expect(second).to eq(first)
    end
  end

  describe "schema validation" do
    # Minimal valid provider descriptor — mutate via `provider_overrides` to
    # trigger exactly one validation failure per example.
    def valid_provider(overrides = {})
      {
        label: "OpenCode Zen",
        wire: "openai_chat",
        base_url: "https://opencode.ai/zen/v1",
        auth: "bearer",
        models_endpoint: "/models",
        capabilities: { streaming: true, reasoning: "none" },
        pinned_models: %w[a b]
      }.merge(overrides)
    end

    def valid_doc(doc_overrides: {}, provider_overrides: {})
      {
        schema_version: 1,
        providers: { opencode: valid_provider(provider_overrides) }
      }.merge(doc_overrides)
    end

    # Stubs the seam load! reads through, clears memoization so the next
    # access re-parses the stubbed doc, then always reload!s afterwards so
    # later examples never see the synthetic document.
    def with_stubbed_yaml(doc)
      allow(YAML).to receive(:safe_load_file).and_return(doc)
      described_class.reload!
      yield
    ensure
      described_class.reload!
    end

    it "raises naming the offending path for an unknown top-level key" do
      with_stubbed_yaml(valid_doc.merge(bogus: true)) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /bogus/)
      end
    end

    it "raises naming the offending path for the wrong schema_version" do
      with_stubbed_yaml(valid_doc(doc_overrides: { schema_version: 2 })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /schema_version/)
      end
    end

    it "raises naming the offending path for an unknown per-provider key" do
      with_stubbed_yaml(valid_doc(provider_overrides: { bogus: true })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode.*bogus/)
      end
    end

    it "raises naming the offending path for a bad wire value" do
      with_stubbed_yaml(valid_doc(provider_overrides: { wire: "bogus" })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode\.wire/)
      end
    end

    it "raises naming the offending path for a bad auth value" do
      with_stubbed_yaml(valid_doc(provider_overrides: { auth: "bogus" })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode\.auth/)
      end
    end

    it "raises naming the offending path for an http:// base_url" do
      with_stubbed_yaml(valid_doc(provider_overrides: { base_url: "http://opencode.ai/zen/v1" })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode\.base_url/)
      end
    end

    it "raises naming the offending path for capabilities.reasoning outside the allowed set" do
      with_stubbed_yaml(
        valid_doc(provider_overrides: { capabilities: { streaming: true, reasoning: "bogus" } })
      ) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode\.capabilities\.reasoning/)
      end
    end

    it "raises naming the offending path when pinned_models is not an Array of Strings" do
      with_stubbed_yaml(valid_doc(provider_overrides: { pinned_models: [ "a", 1 ] })) do
        expect { described_class.provider_names }
          .to raise_error(described_class::InvalidConfig, /providers\.opencode\.pinned_models/)
      end
    end
  end
end
