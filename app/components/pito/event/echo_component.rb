# frozen_string_literal: true

module Pito
  module Event
    class EchoComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      def initialize(payload: {})
        @text = payload[:text].to_s
      end
    end
  end
end
