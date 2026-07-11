# frozen_string_literal: true

module Pito
  module Ai
    # The /config ai picker overlay — OpenCode-style model selection for one AI
    # provider, pito-terminal dressed: square corners, mono, no hover theatrics.
    #
    # Two states, both server-rendered and toggled live by pito--ai-picker:
    #   * no key   → a masked API-key prompt (enter saves via PATCH /settings/ai;
    #                the key is stored in AppSetting's encrypted key/value store
    #                and never travels back down).
    #   * key set  → the model list (live catalog with pinned fallbacks), search
    #                filter, ↑/↓ + enter to pick, ctrl+x clears the stored key.
    #
    # Dumb by design: the caller (the /config ai fast-path) assembles state and
    # passes it in — the component reads no globals, so it renders identically
    # in specs and previews.
    class PickerComponent < ViewComponent::Base
      # @param provider     [Symbol]  registry name (e.g. :opencode)
      # @param label        [String]  display label (e.g. "OpenCode Zen")
      # @param models       [Array<Hash>] { id: String, pinned: Boolean } rows
      # @param active_model [String, nil] currently selected model id
      # @param key_present  [Boolean] whether an API key is stored
      def initialize(provider:, label:, models:, active_model: nil, key_present: false)
        @provider     = provider.to_s
        @label        = label
        @models       = models
        @active_model = active_model
        @key_present  = key_present
      end

      attr_reader :provider, :label, :models, :active_model

      def key_present?
        @key_present
      end

      def active?(model_id)
        model_id == @active_model
      end
    end
  end
end
