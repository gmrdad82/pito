# frozen_string_literal: true

module Pito
  module Event
    class UserMessageComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      # @param body [String, nil] legacy param, replaced by payload.
      def initialize(payload: {}, body: nil)
        @body = body || payload[:text].to_s
      end
    end
  end
end
