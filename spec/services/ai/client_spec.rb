# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Client do
  describe ".current" do
    it "raises NotConfigured when no model is selected" do
      expect { described_class.current }
        .to raise_error(described_class::NotConfigured, /no model selected/)
    end

    it "raises NotConfigured when the provider has no API key" do
      AppSetting.set("ai_model", "claude-sonnet-5")

      expect { described_class.current }
        .to raise_error(described_class::NotConfigured, /no opencode API key/)
    end

    it "resolves the default provider with a stored model and key" do
      AppSetting.set("ai_model", "claude-sonnet-5")
      AppSetting.set("opencode_api_key", "sk-test")

      client = described_class.current
      expect(client.provider).to eq("opencode")
      expect(client.model).to eq("claude-sonnet-5")
    end

    it "reflects a mid-conversation model switch on the next resolution" do
      AppSetting.set("ai_model", "claude-sonnet-5")
      AppSetting.set("opencode_api_key", "sk-test")
      described_class.current

      AppSetting.set("ai_model", "big-pickle")
      expect(described_class.current.model).to eq("big-pickle")
    end
  end

  describe "#chat" do
    it "delegates to the wire with the resolved model and effort" do
      wire = instance_double(Ai::Wire::OpenAiChat)
      allow(Ai::Wire::OpenAiChat).to receive(:new)
        .with(base_url: "https://opencode.ai/zen/v1", api_key: "sk-test",
              auth: "bearer", reasoning: "none")
        .and_return(wire)

      client   = described_class.new(provider: "opencode", model: "m-1",
                                     api_key: "sk-test", effort: "high")
      messages = [ { role: "user", content: "hi" } ]
      expect(wire).to receive(:chat)
        .with(messages:, model: "m-1", tools: nil, system: nil, effort: "high")

      client.chat(messages:)
    end
  end

  describe "wire routing" do
    it "instantiates the Anthropic wire for an anthropic_messages provider" do
      allow(Ai::ProviderRegistry).to receive(:provider).with(:fakeprov).and_return(
        { wire: "anthropic_messages", base_url: "https://api.example/v1",
          auth: "x_api_key", capabilities: { reasoning: "budget" } }
      )
      expect(Ai::Wire::AnthropicMessages).to receive(:new)
        .with(base_url: "https://api.example/v1", api_key: "k",
              auth: "x_api_key", reasoning: "budget")

      described_class.new(provider: "fakeprov", model: "m", api_key: "k")
    end
  end
end
