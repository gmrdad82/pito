# frozen_string_literal: true

module Ai
  # Assembles the AI model picker's complete state — every provider with its
  # key status, reasoning capability, and live model catalog (fetched only
  # where a key allows, or OpenCode Zen which lists unauthenticated), plus
  # the active pick, its per-model effort, favorites, recents, and the
  # models THIS conversation's answers already used (the "Conversation"
  # group's ✨ trail).
  #
  # ONE assembly, two faces: the web overlay (/config ai → turbo partial)
  # and the JSON read path (GET /settings/ai.json — pito-tui's picker).
  # Keep them identical by construction: both render exactly this hash.
  class PickerState
    CONVERSATION_MODELS_LIMIT = 5

    def self.call(conversation: nil)
      new(conversation:).call
    end

    def initialize(conversation: nil)
      @conversation = conversation
    end

    def call
      active_provider = AppSetting.get("ai_provider").presence || "opencode"
      active_model    = AppSetting.get("ai_model")
      active_entry    = active_model.presence && "#{active_provider}/#{active_model}"

      {
        providers:           providers,
        active_provider:     active_provider,
        active_model:        active_model,
        effort:              active_entry && AppSetting.ai_effort_for(active_entry),
        favorites:           AppSetting.ai_favorites,
        recents:             AppSetting.ai_recents,
        conversation_models: conversation_models
      }
    end

    private

    def providers
      Ai::ProviderRegistry.provider_names.map do |name|
        config      = Ai::ProviderRegistry.provider(name)
        key_present = AppSetting.get("#{name}_api_key").present?
        {
          provider:    name.to_s,
          label:       config[:label],
          key_present: key_present,
          reasoning:   config.dig(:capabilities, :reasoning).to_s,
          # Live fetch only where it can succeed (a key on file — or OpenCode
          # Zen, which lists models unauthenticated); keyless providers list
          # NOTHING — the picker renders the key-gate copy line instead of
          # pinned placeholders (owner call), and never stacks doomed requests.
          models:      key_present || name == :opencode ? Ai::ModelCatalog.models(provider: name) : []
        }
      end
    end

    # Models this conversation's answers already used (✨ badge stamps),
    # newest first, deduped.
    def conversation_models
      return [] unless @conversation

      @conversation.events.where(kind: "ai")
                   .order(id: :desc).limit(50)
                   .filter_map { |e|
                     p = e.payload["provider"].presence
                     m = e.payload["model"].presence
                     "#{p}/#{m}" if p && m
                   }.uniq.first(CONVERSATION_MODELS_LIMIT)
    end
  end
end
