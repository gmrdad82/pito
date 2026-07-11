# frozen_string_literal: true

module Ai
  # Resolves the ACTIVE provider/model/key into a ready wire adapter — the one
  # entry point the orchestrator calls. Resolution happens per call (nothing is
  # memoized), so switching provider/model/effort mid-conversation via
  # /config ai takes effect on the very next turn.
  #
  #   client = Ai::Client.current   # raises NotConfigured when unset
  #   client.chat(messages:, tools:, system:)  # => Ai::Wire::Response
  #
  # WHICH provider/model is active lives in AppSetting (key/value store, set by
  # /config ai); HOW to reach the provider lives in Ai::ProviderRegistry.
  class Client
    # Raised when provider, model, or API key is missing — the caller surfaces
    # it as a "configure AI first" message (copy lands with the orchestrator).
    class NotConfigured < StandardError; end

    WIRES = {
      "openai_chat"        => Ai::Wire::OpenAiChat,
      "anthropic_messages" => Ai::Wire::AnthropicMessages
    }.freeze

    DEFAULT_PROVIDER = "opencode"

    attr_reader :provider, :model, :effort

    def self.current
      provider = AppSetting.get("ai_provider").presence || DEFAULT_PROVIDER
      model    = AppSetting.get("ai_model").presence
      effort   = AppSetting.get("ai_effort").presence
      key      = AppSetting.get("#{provider}_api_key").presence

      raise NotConfigured, "no model selected (run /config ai)" if model.nil?
      raise NotConfigured, "no #{provider} API key (run /config ai)" if key.nil?

      new(provider:, model:, effort:, api_key: key)
    end

    def initialize(provider:, model:, api_key:, effort: nil)
      @provider = provider.to_s
      @model    = model
      @effort   = effort

      config = Ai::ProviderRegistry.provider(@provider.to_sym)
      @wire  = WIRES.fetch(config[:wire].to_s).new(
        base_url:  config[:base_url],
        api_key:   api_key,
        auth:      config[:auth].to_s,
        reasoning: config.dig(:capabilities, :reasoning).to_s
      )
    end

    # One completed API call → Ai::Wire::Response. Raises Ai::Wire::Error on
    # any HTTP/parse/network failure — the orchestrator owns retries/surfacing.
    def chat(messages:, tools: nil, system: nil)
      @wire.chat(messages:, model: @model, tools:, system:, effort: @effort)
    end

    # Wire-native history builders (each wire encodes tool traffic differently;
    # the orchestrator never assembles those hashes itself).
    def assistant_tool_message(response)
      @wire.assistant_tool_message(response)
    end

    def tool_result_message(tool_call, content, error: false)
      @wire.tool_result_message(tool_call, content, error:)
    end
  end
end
