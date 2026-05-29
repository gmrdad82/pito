# frozen_string_literal: true

module Pito
  module Shell
    class ChatboxComponent < ViewComponent::Base
      # @param state [Symbol] one of :default, :start — affects placeholder text.
      # @param placeholder_key [String] i18n key for the placeholder text in line 1.
      # @param filter [Hash, nil] optional filter context rendered as line 2.
      #   Known keys: :channel (String), :period (String).
      # @param input_data [Hash, nil] Stimulus data attributes for the text input
      #   (e.g. `{ pito__chat_form_target: "inputField" }`).
      def initialize(state: :default, placeholder_key: nil, filter: nil, input_data: nil)
        @state = state
        @placeholder_key = placeholder_key
        @filter = filter
        @input_data = input_data
      end
    end
  end
end
