# frozen_string_literal: true

module Pito
  module Shell
    class ChatboxComponent < ViewComponent::Base
      # @param state [Symbol] one of :default, :start — affects placeholder text.
      # @param placeholder_key [String] i18n key for the placeholder text in line 1.
      # @param filter [Hash, nil] optional filter context rendered as line 2.
      #   Known keys: :channel (String), :period (String).
      def initialize(state: :default, placeholder_key: nil, filter: nil)
        @state = state
        @placeholder_key = placeholder_key
        @filter = filter
      end
    end
  end
end
