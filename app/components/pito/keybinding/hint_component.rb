# frozen_string_literal: true

module Pito
  module Keybinding
    # Renders a keyboard shortcut + description pair with canonical spacing.
    # Used everywhere shortcuts are shown: expand hints, mini status, errors.
    class HintComponent < ViewComponent::Base
      def initialize(shortcut:, description:, shortcut_data: {}, description_id: nil, description_data: {})
        @shortcut       = shortcut
        @description    = description
        @shortcut_data  = shortcut_data
        @description_id = description_id
        @description_data = description_data
      end
    end
  end
end
