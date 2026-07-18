# frozen_string_literal: true

module Pito
  module Ai
    # The /config ai picker overlay — OpenCode-style model selection across
    # EVERY provider in config/pito/ai_providers.yml, pito-terminal dressed:
    # square corners, mono, no hover theatrics.
    #
    # Layout: Conversation (models this conversation's answers already used,
    # only when any exist), Favorites (ctrl+f pins) and Recents lead, then one
    # section per provider — its models when reachable (live list with a key,
    # pinned fallback without) plus a connect row for keyless providers. An
    # effort row ALWAYS renders: the Enter/tap cycler when the ACTIVE provider
    # declares reasoning (effort persists PER MODEL), otherwise a read-only
    # dim line — the provider manages reasoning itself, nothing to cycle.
    # Every selectable row carries data-provider + data-value; pito--ai-picker
    # owns keyboard flow and persistence (PATCH /settings/ai).
    #
    # Dumb by design: the caller (the /config ai fast-path) assembles state and
    # passes it in — the component reads no globals, so it renders identically
    # in specs and previews.
    class PickerComponent < ViewComponent::Base
      # @param providers [Array<Hash>] {provider:, label:, key_present:,
      #   reasoning:, models: [{id:, pinned:}]} rows, registry order
      # @param active_provider [String]  the provider of the active model
      # @param active_model    [String, nil] currently selected model id
      # @param effort          [String, nil] the ACTIVE model's effort (nil = model default)
      # @param favorites       [Array<String>] "provider/model" pins
      # @param recents         [Array<String>] "provider/model", newest first
      # @param conversation_models [Array<String>] "provider/model" this
      #   conversation's :ai answers already used, newest first
      def initialize(providers:, active_provider:, active_model: nil, effort: nil,
                     favorites: [], recents: [], conversation_models: [])
        @providers           = providers
        @active_provider     = active_provider.to_s
        @active_model        = active_model
        @effort              = effort
        @favorites           = favorites
        @recents             = recents
        @conversation_models = conversation_models
      end

      attr_reader :providers, :active_provider, :active_model, :effort, :favorites, :recents,
                  :conversation_models

      def active?(provider, model_id)
        provider.to_s == @active_provider && model_id == @active_model
      end

      def favorite?(provider, model_id)
        @favorites.include?("#{provider}/#{model_id}")
      end

      # "provider/model" entries resolved back to rows (unknown providers —
      # e.g. one removed from the YAML — are silently skipped).
      def resolve_entries(entries)
        by_name = providers.index_by { |p| p[:provider] }
        entries.filter_map do |entry|
          provider, model = entry.split("/", 2)
          next unless model.present? && by_name.key?(provider)

          { provider: provider, label: by_name[provider][:label], id: model }
        end
      end

      # Whether the ACTIVE provider supports a real reasoning cycle. The
      # effort row itself always renders (see class doc); this only decides
      # which of the two branches it renders as — the Enter/tap cycler here,
      # a read-only dim line otherwise (provider manages reasoning itself).
      def effort_cyclable?
        active = providers.find { |p| p[:provider] == @active_provider }
        active && active[:reasoning] != "none"
      end

      def effort_label
        @effort.presence || "model default"
      end
    end
  end
end
