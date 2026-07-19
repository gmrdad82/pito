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
      # Effort is PER MODEL ("provider/model" map) — switching models restores
      # that model's own effort; models without one simply have no entry.
      effort   = model && AppSetting.ai_effort_for("#{provider}/#{model}").presence
      key      = AppSetting.get("#{provider}_api_key").presence

      raise NotConfigured, "no model selected (run /config ai)" if model.nil?
      raise NotConfigured, "no #{provider} API key (run /config ai)" if key.nil?

      new(provider:, model:, effort:, api_key: key)
    end

    # Non-raising readiness check — the presentation-layer twin of #current's
    # raise conditions (model + key present; provider always resolves via
    # DEFAULT_PROVIDER, so it is never itself the missing piece). The single
    # source Pito::Dispatch::Availability's "ai_configured" condition reads,
    # so a palette/help pass can ask "is @ai usable right now?" without
    # wrapping #current in a rescue just to probe it.
    def self.configured?
      provider = AppSetting.get("ai_provider").presence || DEFAULT_PROVIDER
      model    = AppSetting.get("ai_model").presence
      key      = AppSetting.get("#{provider}_api_key").presence

      model.present? && key.present?
    end

    # The active model id (AppSetting "ai_model"), or nil when unset — the
    # presentation-layer fact every @ai label/menu-item reads (the seam
    # Pito::Suggestions::{Catalog,Engine} call ai_model_for).
    def self.active_model
      AppSetting.get("ai_model").presence
    end

    # The "@ai" token as it should be PRESENTED wherever it renders in a
    # palette or a reply-vocabulary listing: the bare dispatch token with the
    # ACTIVE model parenthesized on, e.g. "@ai(claude-sonnet-5)" — display
    # only, every dispatcher still matches on the bare "@ai" token, never
    # this string. #configured? (and therefore Pito::Dispatch::Availability's
    # "ai_configured") is what keeps an unready @ai out of a palette in the
    # first place, so `model` is normally present here — but this stays total
    # (falls back to the bare token) rather than assume that gate ran.
    def self.ai_label(model: active_model)
      model ? "@ai(#{model})" : "@ai"
    end

    def initialize(provider:, model:, api_key:, effort: nil)
      @provider = provider.to_s
      @model    = model
      @effort   = effort

      config  = Ai::ProviderRegistry.provider(@provider.to_sym)
      @config = config
      @wire   = WIRES.fetch(config[:wire].to_s).new(
        base_url:  config[:base_url],
        api_key:   api_key,
        auth:      config[:auth].to_s,
        reasoning: config.dig(:capabilities, :reasoning).to_s
      )
    end

    # One completed API call → Ai::Wire::Response. Raises Ai::Wire::Error on
    # any HTTP/parse/network failure — the orchestrator owns retries/surfacing.
    def chat(messages:, tools: nil, system: nil, &on_arguments_fragment)
      @wire.chat(messages:, model: @model, tools:, system:, effort: @effort, &on_arguments_fragment)
    end

    # True when the provider declares SSE support (capabilities.streaming in
    # ai_providers.yml) — the orchestrator only hands the wires a streaming
    # block when this holds, so non-SSE providers keep the one-shot path.
    def streaming?
      @config.dig(:capabilities, :streaming) == true
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
