# frozen_string_literal: true

module Pito
  module Event
    # Braille spinner shown while a confirmation action is processing.
    class ConfirmationSpinnerComponent < ViewComponent::Base
      def initialize(frames_json:, word:)
        @frames_json = frames_json
        @word        = word
      end
    end
  end
end
