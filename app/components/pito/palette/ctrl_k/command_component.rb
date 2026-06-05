# frozen_string_literal: true

module Pito
  module Palette
    module CtrlK
      # Renders a single selectable command row in the palette.
      # label_key: i18n key for the human-readable label
      # insert:    the text pre-filled into the chatbox on Enter
      class CommandComponent < ViewComponent::Base
        def initialize(label_key:, insert:)
          @label_key = label_key
          @insert    = insert
        end

        def label = t(@label_key)
        def searchable = "#{label} #{@insert}".downcase
      end
    end
  end
end
