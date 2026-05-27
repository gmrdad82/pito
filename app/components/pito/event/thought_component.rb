# frozen_string_literal: true

module Pito
  module Event
    class ThoughtComponent < ViewComponent::Base
      # @param body [String] the thought text.
      # @param duration [String, nil] optional duration e.g. "4.2s".
      def initialize(body:, duration: nil)
        @body = body
        @duration = duration
      end
    end
  end
end
