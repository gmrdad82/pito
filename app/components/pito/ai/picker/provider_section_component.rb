# frozen_string_literal: true

module Pito
  module Ai
    module Picker
      # One provider's section in the /config ai picker: label + key chip, the
      # connect row + hidden key input (revealed by pito--ai-picker), and the
      # provider's model rows.
      class ProviderSectionComponent < ViewComponent::Base
        # @param provider        [Hash] {provider:, label:, key_present:, models:}
        # @param active_provider [String]
        # @param active_model    [String, nil]
        # @param favorites       [Array<String>] "provider/model" pins
        def initialize(provider:, active_provider:, active_model:, favorites: [])
          @p               = provider
          @active_provider = active_provider
          @active_model    = active_model
          @favorites       = favorites
        end

        def name        = @p[:provider]
        def label       = @p[:label]
        def models      = @p[:models]
        def key_present? = @p[:key_present]

        def active?(model_id)
          name == @active_provider && model_id == @active_model
        end

        def favorite?(model_id)
          @favorites.include?("#{name}/#{model_id}")
        end
      end
    end
  end
end
