# frozen_string_literal: true

module Pito
  module Shell
    module MiniStatus
      # Delegates to the canonical Pito::Keybinding::HintComponent so
      # spacing stays consistent across mini-status, expand hints, and errors.
      class KeyHintComponent < ViewComponent::Base
        def initialize(hint:, label:, hint_data: {}, label_id: nil)
          @hint      = hint
          @label     = label
          @hint_data = hint_data
          @label_id  = label_id
        end

        def call
          render Pito::Keybinding::HintComponent.new(
            shortcut:      @hint,
            description:   @label,
            shortcut_data:   @hint_data,
            description_id:  @label_id
          )
        end
      end
    end
  end
end
